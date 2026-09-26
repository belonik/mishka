import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// UI-level state: what is selected in the sidebar, the search string, and the toast/error
/// channel. Note data itself lives in `NoteStore`.
final class AppState: ObservableObject {

    let store: NoteStore

    /// Views bind to `AppState`, not to `NoteStore`, so every change made directly on the
    /// store (selecting a note, editing, trashing) has to be republished here. Without
    /// this, the model updates but SwiftUI is never told and clicks appear to do nothing.
    private var storeSubscription: AnyCancellable?

    @Published var sidebarSelection: SidebarItem = .all
    @Published var searchQuery: String = ""
    @Published var searchFieldFocused: Bool = false
    @Published var expandedTags: Set<String> = []
    @Published var statusMessage: String?
    @Published var renamingNoteID: UUID?
    /// Bumped by the Find Notes menu command; the search field watches it.
    @Published var searchFocusToken: Int = 0
    /// Paths of files opened in place, newest first — the "history" the app keeps.
    @Published var recentFilePaths: [String] = []

    private let recentFilesKey = "recentFilePaths"
    private let recentFilesLimit = 15

    private let statusDebouncer = Debouncer()

    init(store: NoteStore = NoteStore()) {
        self.store = store
        storeSubscription = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        recentFilePaths = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        expandedTags = Set(store.tagTree.map(\.id))
        // Always open in "All Notes". Deriving the section from the selected note's first
        // tag used to drop the user into an arbitrary tag on every launch.
        sidebarSelection = .all
    }

    // MARK: - Selection helpers

    var selectedNote: Note? {
        guard let id = store.selectedNoteID else { return nil }
        return store.note(id: id)
    }

    func select(_ note: Note) {
        store.selectedNoteID = note.id
    }

    func select(_ item: SidebarItem) {
        sidebarSelection = item
        if case .trash = item { return }
        // Keep the note list and the editor consistent after switching sections.
        let visible = visibleNotes
        if let current = store.selectedNoteID, visible.contains(where: { $0.id == current }) {
            return
        }
        store.selectedNoteID = visible.first?.id
    }

    var visibleNotes: [Note] {
        store.filtered(selection: sidebarSelection, query: searchQuery, sort: sortOrder)
    }

    @Published var sortOrder: SortOrder = SortOrder()

    func refreshSortOrder(_ order: SortOrder) {
        sortOrder = order
    }

    // MARK: - Commands

    func newNote() {
        if case .trash = sidebarSelection { sidebarSelection = .all }
        let note = store.createNote()
        status("New note created")
        _ = note
    }

    func newNoteFromSelection() {
        guard let note = selectedNote else {
            newNote()
            return
        }
        let lines = note.text.split(separator: "\n", omittingEmptySubsequences: false)
        let remainder = lines.dropFirst().joined(separator: "\n")
        store.update(id: note.id, text: remainder.isEmpty ? "\n" : remainder)
    }

    func trashSelected() {
        guard let note = selectedNote else { return }
        if note.isExternal {
            forget(note: note)
        } else {
            store.moveToTrash(id: note.id)
            status("Moved to trash")
        }
    }

    func togglePinSelected() {
        guard let note = selectedNote else { return }
        store.togglePinned(id: note.id)
        status(note.isPinned ? "Unpinned" : "Pinned")
    }

    func selectNextNote(offset: Int) {
        let notes = visibleNotes
        guard !notes.isEmpty else { return }
        let currentIndex = notes.firstIndex { $0.id == store.selectedNoteID } ?? -1
        let next = (currentIndex + offset + notes.count) % notes.count
        store.selectedNoteID = notes[next].id
    }

    // MARK: - Files opened in place

    /// Asks for a markdown file and opens it where it lies. Nothing is copied, so the
    /// original stays the single source of truth and other editors keep working on it.
    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Markdown File"
        panel.prompt = "Open"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        var types: [UTType] = [.plainText, .text]
        if let markdown = UTType(filenameExtension: "md") { types.insert(markdown, at: 0) }
        if let markdownLong = UTType(filenameExtension: "markdown") { types.insert(markdownLong, at: 1) }
        panel.allowedContentTypes = types
        guard panel.runModal() == .OK else { return }
        openFiles(panel.urls)
    }

    func openFiles(_ urls: [URL]) {
        let files = urls.filter { url in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return !isDirectory.boolValue
        }
        guard !files.isEmpty else { return }

        let opened = store.openExternalFiles(files)
        guard let last = opened.last else {
            if let error = store.lastError { status(error) }
            return
        }
        remember(opened.compactMap(\.externalPath))
        // Make sure the file that was just opened is actually visible in the list.
        if !visibleNotes.contains(where: { $0.id == last.id }) {
            sidebarSelection = .all
            searchQuery = ""
        }
        status(opened.count == 1 ? "Opened \(last.title)" : "Opened \(opened.count) files")
    }

    func openRecentFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            recentFilePaths.removeAll { $0 == path }
            persistRecentFiles()
            status("File is gone: \((path as NSString).lastPathComponent)")
            return
        }
        openFiles([url])
    }

    /// Stops tracking a file. The file itself is left untouched on disk.
    func forget(note: Note) {
        guard note.isExternal else { return }
        store.forget(id: note.id)
        recentFilePaths.removeAll { $0 == note.externalPath }
        persistRecentFiles()
        status("Removed \((note.externalFileName ?? "file")) from Mishka — the file itself is untouched")
    }

    func clearRecentFiles() {
        recentFilePaths.removeAll()
        persistRecentFiles()
    }

    /// Re-reads bound files; used when the app comes back to the foreground.
    func refreshExternalNotes() {
        store.refreshExternalNotes()
    }

    private func remember(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        var updated = paths
        updated.append(contentsOf: recentFilePaths.filter { !paths.contains($0) })
        recentFilePaths = Array(updated.prefix(recentFilesLimit))
        persistRecentFiles()
    }

    private func persistRecentFiles() {
        UserDefaults.standard.set(recentFilePaths, forKey: recentFilesKey)
    }

    func focusSearch() {
        if case .trash = sidebarSelection { sidebarSelection = .all }
        searchFocusToken += 1
    }

    func toggleTagExpansion(_ id: String) {
        if expandedTags.contains(id) {
            expandedTags.remove(id)
        } else {
            expandedTags.insert(id)
        }
    }

    func exportCurrentNote(format: ExportFormat) {
        guard let note = selectedNote else { return }
        Exporter.export(note: note, format: format, settings: nil) { message in
            self.status(message)
        }
    }

    func status(_ message: String) {
        statusMessage = message
        statusDebouncer.schedule(2.4) { [weak self] in
            self?.statusMessage = nil
        }
    }

    var sidebarCounts: [SidebarItem: Int] {
        [
            .all: store.activeNotes.count,
            .pinned: store.pinnedCount,
            .files: store.filesCount,
            .untagged: store.untaggedCount,
            .todo: store.todoCount,
            .today: store.todayCount,
            .trash: store.trashedNotes.count,
        ]
    }
}
