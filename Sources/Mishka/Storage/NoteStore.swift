import AppKit
import Foundation
import SwiftUI

/// Owns the note library. Notes live on disk as plain `.md` files (one per note) inside a
/// vault directory, with a small JSON index holding the metadata that markdown cannot
/// express (creation date, pin state, trash state). If the index is ever lost it is
/// rebuilt by scanning the vault, so the user's data is never trapped in a proprietary store.
final class NoteStore: ObservableObject {

    @Published private(set) var notes: [Note] = [] {
        didSet {
            // Cheap memoisation: several views ask for these during one render pass,
            // and the first keystroke in the editor invalidates them all.
            cachedTagTree = nil
            cachedFlatTagCounts = nil
        }
    }

    private var cachedTagTree: [TagNode]?
    private var cachedFlatTagCounts: [String: Int]?
    @Published var selectedNoteID: UUID?
    @Published private(set) var lastError: String?

    let rootURL: URL
    private let notesDir: URL
    private let trashDir: URL
    private let indexURL: URL

    private let ioQueue = DispatchQueue(label: "app.mishka.io", qos: .utility)
    private let indexDebouncer = Debouncer()

    // MARK: - Init

    init(rootURL: URL? = nil) {
        let root = rootURL ?? NoteStore.defaultRoot()
        self.rootURL = root
        self.notesDir = root.appendingPathComponent("notes", isDirectory: true)
        self.trashDir = root.appendingPathComponent("trash", isDirectory: true)
        self.indexURL = root.appendingPathComponent("library.json")

        prepareDirectories()
        load()
    }

    /// The vault location. `--vault <path>` (or `MISHKA_VAULT`) points the app at a
    /// different folder, which is handy for testing and for keeping several libraries.
    static func defaultRoot() -> URL {
        let environment = ProcessInfo.processInfo.environment["MISHKA_VAULT"]
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--vault"), index + 1 < arguments.count {
            return URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let environment, !environment.isEmpty {
            return URL(fileURLWithPath: (environment as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Mishka", isDirectory: true)
    }

    private func prepareDirectories() {
        let fm = FileManager.default
        for dir in [rootURL, notesDir, trashDir] {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Loading

    private func load() {
        let fm = FileManager.default
        var index = LibraryIndex()
        if let data = try? Data(contentsOf: indexURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(LibraryIndex.self, from: data) {
                index = decoded
            }
        }

        var recordsByID: [UUID: NoteRecord] = [:]
        for record in index.records { recordsByID[record.id] = record }

        var loaded: [Note] = []
        var seen = Set<UUID>()

        func ingest(directory: URL, trashed: Bool) {
            let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey], options: [.skipsHiddenFiles])) ?? []
            for file in files where file.pathExtension.lowercased() == "md" {
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
                let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                var note = Note(
                    id: id,
                    text: text,
                    createdAt: values?.creationDate ?? Date(),
                    modifiedAt: values?.contentModificationDate ?? Date(),
                    isTrashed: trashed
                )
                if let record = recordsByID[id] {
                    note = record.applied(to: note)
                    // A file that physically sits in `trash/` is trashed regardless of the index.
                    note.isTrashed = trashed
                }
                if trashed { note.trashedAt = note.trashedAt ?? note.modifiedAt }
                note.refreshDerived()
                loaded.append(note)
                seen.insert(id)
            }
        }

        ingest(directory: notesDir, trashed: false)
        ingest(directory: trashDir, trashed: true)

        // Files the user opened in place are re-read from wherever they live. A file that
        // is temporarily unavailable keeps its history entry and is marked as missing.
        for record in index.records {
            guard let path = record.externalPath, !seen.contains(record.id) else { continue }
            let url = URL(fileURLWithPath: path)
            let exists = fm.fileExists(atPath: url.path)
            let text = exists ? ((try? String(contentsOf: url, encoding: .utf8)) ?? "") : ""
            var note = Note(
                id: record.id,
                text: text,
                createdAt: record.createdAt,
                modifiedAt: record.modifiedAt,
                externalPath: path,
                isMissing: !exists
            )
            note = record.applied(to: note)
            note.isTrashed = false
            note.trashedAt = nil
            note.refreshDerived()
            loaded.append(note)
            seen.insert(record.id)
        }

        notes = loaded
        // Reopen on a note that is actually in the library — a selection that was trashed
        // before quitting must not come back as the open note.
        if let selected = index.selectedNoteID,
           seen.contains(selected),
           let restored = notes.first(where: { $0.id == selected }),
           !restored.isTrashed {
            selectedNoteID = selected
        } else {
            selectedNoteID = notes.filter { !$0.isTrashed }.sorted { $0.modifiedAt > $1.modifiedAt }.first?.id
        }

        if notes.isEmpty && !fm.fileExists(atPath: indexURL.path) {
            seedWelcomeNote()
        }
        saveIndex()
    }

    private func seedWelcomeNote() {
        createNote(initialText: NoteStore.welcomeText, select: true)
    }

    // MARK: - Queries

    var activeNotes: [Note] { notes.filter { !$0.isTrashed } }
    var trashedNotes: [Note] { notes.filter { $0.isTrashed } }
    var pinnedCount: Int { activeNotes.filter(\.isPinned).count }
    var filesCount: Int { activeNotes.filter(\.isExternal).count }
    var untaggedCount: Int { activeNotes.filter { $0.tags.isEmpty }.count }
    var todoCount: Int { activeNotes.filter(\.hasOpenTask).count }
    var todayCount: Int {
        activeNotes.filter { Calendar.current.isDateInToday($0.modifiedAt) }.count
    }

    var tagTree: [TagNode] {
        if let cachedTagTree { return cachedTagTree }
        let tree = TagNode.build(from: activeNotes.map(\.tags))
        cachedTagTree = tree
        return tree
    }

    /// Every distinct tag with the number of notes carrying it (nested counts included).
    var flatTagCounts: [String: Int] {
        if let cachedFlatTagCounts { return cachedFlatTagCounts }
        var counts: [String: Int] = [:]
        for note in activeNotes {
            var seen = Set<String>()
            for tag in note.tags {
                let components = tag.split(separator: "/").map(String.init)
                for index in components.indices {
                    let path = components[0...index].joined(separator: "/")
                    if seen.insert(path).inserted { counts[path, default: 0] += 1 }
                }
            }
        }
        cachedFlatTagCounts = counts
        return counts
    }

    func note(id: UUID) -> Note? { notes.first { $0.id == id } }

    func index(of id: UUID) -> Int? { notes.firstIndex { $0.id == id } }

    /// Notes matching the sidebar selection, the search query and the sort order.
    func filtered(
        selection: SidebarItem,
        query: String,
        sort: SortOrder
    ) -> [Note] {
        var pool: [Note]

        switch selection {
        case .trash:
            pool = notes.filter(\.isTrashed)
        case .all:
            pool = activeNotes
        case .pinned:
            pool = activeNotes.filter(\.isPinned)
        case .files:
            pool = activeNotes.filter(\.isExternal)
        case .untagged:
            pool = activeNotes.filter { $0.tags.isEmpty }
        case .todo:
            pool = activeNotes.filter(\.hasOpenTask)
        case .today:
            pool = activeNotes.filter { Calendar.current.isDateInToday($0.modifiedAt) }
        case .locked:
            pool = activeNotes.filter(\.isLocked)
        case .tag(let path):
            pool = activeNotes.filter { note in
                note.tags.contains { $0 == path || $0.hasPrefix(path + "/") }
            }
        }

        if !query.isEmpty {
            pool = pool.filter { $0.matches(query: query) }
        }

        let ascending = sort.ascending
        pool.sort { a, b in
            if selection != .trash, a.isPinned != b.isPinned { return a.isPinned }
            switch sort.field {
            case .modified:
                return ascending ? a.modifiedAt < b.modifiedAt : a.modifiedAt > b.modifiedAt
            case .created:
                return ascending ? a.createdAt < b.createdAt : a.createdAt > b.createdAt
            case .title:
                let result = a.title.localizedStandardCompare(b.title)
                return ascending ? result == .orderedAscending : result == .orderedDescending
            }
        }
        return pool
    }

    // MARK: - Mutations

    @discardableResult
    func createNote(initialText: String = "", select: Bool = true) -> Note {
        var note = Note(text: initialText.isEmpty ? "\n" : initialText)
        note.refreshDerived()
        notes.append(note)
        write(note)
        if select { selectedNoteID = note.id }
        saveIndex()
        return note
    }

    /// Applies an edit coming from the editor. `touch` controls whether the modification
    /// date is bumped (it is not when the user is merely toggling a checkbox in place).
    func update(id: UUID, text: String, touch: Bool = true) {
        guard let position = index(of: id) else { return }
        var note = notes[position]
        guard note.text != text else { return }
        note.text = text
        if touch { note.modifiedAt = Date() }
        note.refreshDerived()
        notes[position] = note
        write(note)
        scheduleIndexSave()
    }

    func setPinned(_ pinned: Bool, id: UUID) {
        guard let position = index(of: id) else { return }
        notes[position].isPinned = pinned
        scheduleIndexSave()
    }

    func togglePinned(id: UUID) {
        guard let note = note(id: id) else { return }
        setPinned(!note.isPinned, id: id)
    }

    func setLocked(_ locked: Bool, id: UUID) {
        guard let position = index(of: id) else { return }
        notes[position].isLocked = locked
        scheduleIndexSave()
    }

    func moveToTrash(id: UUID) {
        guard let position = index(of: id) else { return }
        if notes[position].isExternal {
            // The file belongs to the user and stays exactly where it is.
            forget(id: id)
            return
        }
        let source = fileURL(for: notes[position])          // …/notes/<id>.md
        notes[position].isTrashed = true
        notes[position].trashedAt = Date()
        notes[position].isPinned = false
        let note = notes[position]
        let destination = fileURL(for: note)                // …/trash/<id>.md
        let text = note.text
        ioQueue.async {
            try? text.write(to: destination, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: source)
        }
        if selectedNoteID == id { selectNeighbour(of: position) }
        saveIndex()
    }

    func restore(id: UUID) {
        guard let position = index(of: id) else { return }
        let source = fileURL(for: notes[position])          // …/trash/<id>.md
        notes[position].isTrashed = false
        notes[position].trashedAt = nil
        notes[position].modifiedAt = Date()
        let note = notes[position]
        let destination = fileURL(for: note)                // …/notes/<id>.md
        let text = note.text
        ioQueue.async {
            try? text.write(to: destination, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: source)
        }
        saveIndex()
    }

    func deletePermanently(id: UUID) {
        guard let position = index(of: id) else { return }
        let note = notes[position]
        if !note.isExternal {
            try? FileManager.default.removeItem(at: fileURL(for: note))
        }
        notes.remove(at: position)
        if selectedNoteID == id { selectNeighbour(of: position) }
        saveIndex()
    }

    func emptyTrash() {
        for note in trashedNotes where !note.isExternal {
            try? FileManager.default.removeItem(at: fileURL(for: note))
        }
        notes.removeAll { $0.isTrashed }
        saveIndex()
    }

    func duplicate(id: UUID) {
        guard let note = note(id: id) else { return }
        let copy = createNote(initialText: note.text, select: true)
        if let position = index(of: copy.id) {
            notes[position].createdAt = Date()
            notes[position].modifiedAt = Date()
        }
        saveIndex()
    }

    /// Renames a tag (and every nested tag underneath it) across the whole library.
    func renameTag(from old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#/"))
        guard !trimmed.isEmpty, trimmed != old else { return }
        var changed: [Note] = []
        for position in notes.indices {
            let text = notes[position].text
            let updated = NoteStore.replacingTag(in: text, from: old, to: trimmed)
            guard updated != text else { continue }
            notes[position].text = updated
            notes[position].modifiedAt = Date()
            notes[position].refreshDerived()
            changed.append(notes[position])
        }
        for note in changed { write(note) }
        if !changed.isEmpty { saveIndex() }
    }

    func deleteTag(_ tag: String) {
        var changed: [Note] = []
        for position in notes.indices {
            let text = notes[position].text
            let updated = NoteStore.removingTag(in: text, tag: tag)
            guard updated != text else { continue }
            notes[position].text = updated
            notes[position].modifiedAt = Date()
            notes[position].refreshDerived()
            changed.append(notes[position])
        }
        for note in changed { write(note) }
        if !changed.isEmpty { saveIndex() }
    }

    /// Adds a tag to a note, appending it on its own line if it is not present yet.
    func addTag(_ tag: String, to id: UUID) {
        guard let position = index(of: id) else { return }
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !clean.isEmpty else { return }
        if notes[position].tags.contains(clean) { return }
        var text = notes[position].text
        if !text.hasSuffix("\n") { text += "\n" }
        text += "#" + clean + "\n"
        update(id: id, text: text)
    }

    // MARK: - Files opened in place

    var externalNotes: [Note] { notes.filter(\.isExternal) }

    /// Opens a markdown file where it lies. Nothing is copied into the library: the note
    /// is a live reference, and the app remembers it in `library.json` so it comes back
    /// on the next launch.
    @discardableResult
    func openExternalFile(_ url: URL) -> Note? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let path = resolved.path
        let fm = FileManager.default

        guard fm.fileExists(atPath: path) else {
            lastError = "No such file: \(path)"
            return nil
        }

        // Opening a file that already lives in the vault must not create a second entry.
        if let position = notes.firstIndex(where: {
            $0.externalPath == nil && fileURL(for: $0).resolvingSymlinksInPath().path == path
        }) {
            selectedNoteID = notes[position].id
            return notes[position]
        }

        // Already bound? Refresh it in place instead of creating a second entry.
        if let position = notes.firstIndex(where: { $0.externalPath == path }) {
            let text = (try? String(contentsOf: resolved, encoding: .utf8)) ?? notes[position].text
            notes[position].text = text
            notes[position].isMissing = false
            let values = try? resolved.resourceValues(forKeys: [.contentModificationDateKey])
            notes[position].modifiedAt = values?.contentModificationDate ?? Date()
            notes[position].refreshDerived()
            selectedNoteID = notes[position].id
            saveIndex()
            return notes[position]
        }

        guard let text = try? String(contentsOf: resolved, encoding: .utf8) else {
            lastError = "Could not read \(path)"
            return nil
        }
        let values = try? resolved.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        var note = Note(
            text: text,
            createdAt: values?.creationDate ?? Date(),
            modifiedAt: values?.contentModificationDate ?? Date(),
            externalPath: path
        )
        note.refreshDerived()
        notes.append(note)
        selectedNoteID = note.id
        saveIndex()
        return note
    }

    @discardableResult
    func openExternalFiles(_ urls: [URL]) -> [Note] {
        urls.compactMap { openExternalFile($0) }
    }

    /// Drops the app's reference to a file without touching the file itself.
    func forget(id: UUID) {
        guard let position = index(of: id) else { return }
        notes.remove(at: position)
        if selectedNoteID == id { selectNeighbour(of: position) }
        saveIndex()
    }

    // MARK: - Import / reload

    func importMarkdownFiles(_ urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "txt" || url.pathExtension.lowercased() == "markdown" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            createNote(initialText: text, select: false)
        }
        if let last = activeNotes.sorted(by: { $0.modifiedAt > $1.modifiedAt }).first {
            selectedNoteID = last.id
        }
    }

    /// Re-reads every file from disk, picking up changes made by other editors.
    func reloadFromDisk() {
        saveIndexNow()
        let selected = selectedNoteID
        load()
        if let selected, notes.contains(where: { $0.id == selected }) {
            selectedNoteID = selected
        }
    }

    func revealInFinder(id: UUID) {
        guard let note = note(id: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: note)])
    }

    // MARK: - Persistence

    /// Where the note actually lives. External notes point at the file the user chose,
    /// so every read and write goes straight to that file — nothing is copied.
    func fileURL(for note: Note) -> URL {
        if let path = note.externalPath {
            return URL(fileURLWithPath: path)
        }
        let folder = note.isTrashed ? trashDir : notesDir
        return folder.appendingPathComponent(note.id.uuidString + ".md")
    }

    private func write(_ note: Note) {
        let url = fileURL(for: note)
        let text = note.text
        let isExternal = note.isExternal
        ioQueue.async {
            do {
                if isExternal {
                    try NoteStore.writeExternal(text, to: url)
                } else {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                DispatchQueue.main.async { self.lastError = error.localizedDescription }
            }
        }
    }

    /// Saves into a file the user owns. Writes through symlinks and restores the original
    /// POSIX permissions afterwards, because an atomic replace swaps the inode.
    private static func writeExternal(_ text: String, to url: URL) throws {
        let resolved = url.resolvingSymlinksInPath()
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        try text.write(to: resolved, atomically: true, encoding: .utf8)
        if let permissions = attributes?[.posixPermissions] {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: resolved.path)
        }
    }

    /// Re-reads every bound file whose modification date moved on, and flags the ones
    /// that disappeared. Called when the app becomes active, so edits made elsewhere
    /// show up without the user doing anything.
    func refreshExternalNotes() {
        var changed = false
        for position in notes.indices where notes[position].isExternal {
            guard let path = notes[position].externalPath else { continue }
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else {
                if !notes[position].isMissing {
                    notes[position].isMissing = true
                    changed = true
                }
                continue
            }
            let wasMissing = notes[position].isMissing
            notes[position].isMissing = false
            if wasMissing || modified > notes[position].modifiedAt {
                if let text = try? String(contentsOf: url, encoding: .utf8),
                   text != notes[position].text {
                    notes[position].text = text
                    notes[position].refreshDerived()
                    changed = true
                }
                notes[position].modifiedAt = modified
            }
            if wasMissing { changed = true }
        }
        if changed { saveIndex() }
    }

    private func scheduleIndexSave() {
        indexDebouncer.schedule(0.8) { [weak self] in self?.saveIndexNow() }
    }

    private func saveIndex() { saveIndexNow() }

    func saveIndexNow() {
        let records = notes.map(NoteRecord.init)
        let payload = LibraryIndex(version: 1, records: records, selectedNoteID: selectedNoteID)
        let url = indexURL
        ioQueue.async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(payload) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Called on quit: make sure nothing is still sitting in a debounce buffer.
    func flush() {
        indexDebouncer.flush()
        saveIndexNow()
        ioQueue.sync {}
    }

    /// Picks the next note that is still in the library. Moving a note to the trash keeps
    /// it in `notes`, so without skipping trashed entries the selection would land on the
    /// note the user just deleted.
    private func selectNeighbour(of position: Int) {
        let clamped = min(max(0, position), notes.count)
        if let next = notes.indices.dropFirst(clamped).first(where: { !notes[$0].isTrashed }) {
            selectedNoteID = notes[next].id
        } else if let previous = notes.indices.prefix(clamped).last(where: { !notes[$0].isTrashed }) {
            selectedNoteID = notes[previous].id
        } else {
            selectedNoteID = notes.first(where: { !$0.isTrashed })?.id
        }
    }

    /// Drops trashed notes older than `days` (0 keeps them forever).
    @discardableResult
    func purgeTrash(olderThan days: Int) -> Int {
        guard days > 0 else { return 0 }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return 0 }
        let expired = notes.filter { note in
            note.isTrashed && !note.isExternal && (note.trashedAt ?? note.modifiedAt) < cutoff
        }
        guard !expired.isEmpty else { return 0 }
        for note in expired {
            try? FileManager.default.removeItem(at: fileURL(for: note))
        }
        let identifiers = Set(expired.map(\.id))
        notes.removeAll { identifiers.contains($0.id) }
        if let selected = selectedNoteID, identifiers.contains(selected) {
            selectedNoteID = notes.first(where: { !$0.isTrashed })?.id
        }
        saveIndex()
        return expired.count
    }

    // MARK: - Tag text surgery

    static func replacingTag(in text: String, from old: String, to new: String) -> String {
        var inFence = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                return String(line)
            }
            if inFence { return String(line) }
            return rewriteTags(in: String(line), transform: { tag in
                if tag == old { return new }
                if tag.hasPrefix(old + "/") { return new + String(tag.dropFirst(old.count)) }
                return nil
            })
        }
        return lines.joined(separator: "\n")
    }

    static func removingTag(in text: String, tag: String) -> String {
        var inFence = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                return String(line)
            }
            if inFence { return String(line) }
            return rewriteTags(in: String(line), transform: { candidate in
                if candidate == tag { return "" }
                if candidate.hasPrefix(tag + "/") { return "" }
                return nil
            })
        }
        return lines.joined(separator: "\n")
    }

    /// Rewrites every inline `#tag` in a single line. Returning `nil` keeps the tag as is,
    /// an empty string removes it (and the leftover whitespace is tidied up).
    private static func rewriteTags(in line: String, transform: (String) -> String?) -> String {
        var result = ""
        let chars = Array(line)
        var index = 0
        while index < chars.count {
            let c = chars[index]
            if c == "#" {
                let atStart = index == 0
                let previous = index > 0 ? chars[index - 1] : " "
                let boundaryOK = atStart || previous.isWhitespace || previous == "(" || previous == "["
                if boundaryOK, index + 1 < chars.count, chars[index + 1].isLetter {
                    var end = index + 1
                    while end < chars.count {
                        let n = chars[end]
                        if n.isLetter || n.isNumber || n == "_" || n == "-" || n == "/" { end += 1 } else { break }
                    }
                    var tagChars = Array(chars[(index + 1)..<end])
                    while let last = tagChars.last, last == "/" || last == "-" || last == "_" { tagChars.removeLast() }
                    let tag = String(tagChars)
                    if let replacement = transform(tag) {
                        if !replacement.isEmpty { result += "#" + replacement }
                        index = end
                        continue
                    }
                    result += String(chars[index..<end])
                    index = end
                    continue
                }
            }
            result.append(c)
            index += 1
        }
        return result.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Welcome note

    static let welcomeText = """
    # Добро пожаловать в Mishka 🐻

    Mishka — это заметочник в духе Bear: чистый markdown, живые теги и приятная типографика.

    ## Что попробовать

    - [ ] Нажмите на этот чекбокс — он настоящий
    - [ ] Включите превью кнопкой **⌥⌘3** или переключателем в панели инструментов
    - [ ] Поменяйте тему в настройках (**⌘,**)
    - [x] Создать первую заметку
    - [x] Прочитать это приветствие

    ### Форматирование

    **Жирный**, *курсив*, ***жирный курсив***, ~~зачёркнутый~~, `код в строке` и ==выделение==.

    > Цитата выглядит так — с аккуратной линией слева.

    ```swift
    // Блоки кода не трогаются подсветкой: **звёздочки** внутри остаются как есть
    func greet(_ name: String) -> String {
        "\\(name), привет!"
    }
    ```

    | Возможность | Где найти |
    | --- | --- |
    | Поиск по всем заметкам | **⌘F** |
    | Новая заметка | **⌘N** |
    | Только превью | **⌥⌘3** |
    | В корзину | **⌘⌫** |
    | Настройки | **⌘,** |

    ### Теги

    Теги пишутся прямо в тексте, как в Bear: #идеи #работа/проекты #книги

    Они появляются в левой колонке, поддерживают вложенность и считают заметки.

    Ссылки тоже работают: [bear.app](https://bear.app) и <https://developer.apple.com>

    ---

    Все заметки лежат обычными `.md` файлами в `~/Library/Application Support/Mishka/notes`.
    Ваши данные — ваши файлы.
    """
}
