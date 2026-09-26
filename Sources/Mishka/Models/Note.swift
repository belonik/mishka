import Foundation

/// A single note. The body is stored as plain markdown — the title is simply the first
/// non-empty line, exactly like Bear, so the on-disk `.md` file stays clean and portable.
struct Note: Identifiable, Hashable, Codable {
    var id: UUID
    var text: String
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var isLocked: Bool
    var isTrashed: Bool
    var trashedAt: Date?
    /// Absolute path of the file this note is bound to, when it lives outside the vault.
    /// Such a note is edited in place — nothing is copied into the library.
    var externalPath: String?
    /// The bound file could not be read (moved away, deleted, volume unmounted).
    var isMissing: Bool

    /// Derived, cached for fast list rendering and filtering.
    var title: String
    var snippet: String
    var tags: [String]
    var hasOpenTask: Bool

    init(
        id: UUID = UUID(),
        text: String = "",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isPinned: Bool = false,
        isLocked: Bool = false,
        isTrashed: Bool = false,
        trashedAt: Date? = nil,
        externalPath: String? = nil,
        isMissing: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.isLocked = isLocked
        self.isTrashed = isTrashed
        self.trashedAt = trashedAt
        self.externalPath = externalPath
        self.isMissing = isMissing
        self.title = text.noteTitle
        self.snippet = text.plainSnippet()
        self.tags = Note.scanTags(in: text)
        self.hasOpenTask = Note.scanOpenTask(in: text)
    }

    /// Recomputes every derived field after the body changed.
    mutating func refreshDerived() {
        title = text.noteTitle
        snippet = text.plainSnippet()
        tags = Note.scanTags(in: text)
        hasOpenTask = Note.scanOpenTask(in: text)
    }

    /// True when the note is backed by a file the user opened in place.
    var isExternal: Bool { externalPath != nil }

    /// File name of the bound file, for the UI.
    var externalFileName: String? {
        guard let externalPath else { return nil }
        return (externalPath as NSString).lastPathComponent
    }

    func matches(query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if title.range(of: query, options: options) != nil { return true }
        if text.range(of: query, options: options) != nil { return true }
        return tags.contains { $0.range(of: query, options: options) != nil }
    }

    // MARK: - Tag scanning

    /// Bear-style inline tags: `#` immediately followed by a letter, then letters, digits,
    /// `_`, `-` or `/` for nesting. A heading (`# Title`) never matches because of the space.
    /// Fenced code blocks are ignored.
    static func scanTags(in text: String) -> [String] {
        var found: Set<String> = []
        var inFence = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            for tag in scanTags(inLine: String(rawLine)) { found.insert(tag) }
        }
        return found.sorted()
    }

    private static func scanTags(inLine line: String) -> [String] {
        var result: [String] = []
        let chars = Array(line)
        var index = 0
        var inInlineCode = false
        while index < chars.count {
            let c = chars[index]
            if c == "`" {
                inInlineCode.toggle()
                index += 1
                continue
            }
            if c == "#" && !inInlineCode {
                let atLineStart = index == 0
                let previous = index > 0 ? chars[index - 1] : " "
                let boundaryOK = atLineStart || previous.isWhitespace || previous == "(" || previous == "["
                if boundaryOK, index + 1 < chars.count, chars[index + 1].isLetter {
                    var end = index + 1
                    while end < chars.count {
                        let n = chars[end]
                        if n.isLetter || n.isNumber || n == "_" || n == "-" || n == "/" {
                            end += 1
                        } else {
                            break
                        }
                    }
                    // Trailing separators are not part of the tag.
                    var tagChars = Array(chars[(index + 1)..<end])
                    while let last = tagChars.last, last == "/" || last == "-" || last == "_" {
                        tagChars.removeLast()
                    }
                    if !tagChars.isEmpty {
                        result.append(String(tagChars))
                    }
                    index = end
                    continue
                }
            }
            index += 1
        }
        return result
    }

    /// True when the note contains at least one unchecked `- [ ]` item.
    static func scanOpenTask(in text: String) -> Bool {
        var inFence = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }
            if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("* [ ]") || trimmed.hasPrefix("+ [ ]") {
                return true
            }
        }
        return false
    }
}

// MARK: - Codable bridging for the JSON index

/// Lightweight record persisted in `library.json`. The note body itself lives in a `.md`
/// file, so the index only carries metadata and can always be rebuilt by scanning.
struct NoteRecord: Codable {
    var id: UUID
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var isLocked: Bool
    var isTrashed: Bool
    var trashedAt: Date?
    /// Remembered so the app can re-open a file the user pointed at, without copying it.
    var externalPath: String?

    init(_ note: Note) {
        id = note.id
        createdAt = note.createdAt
        modifiedAt = note.modifiedAt
        isPinned = note.isPinned
        isLocked = note.isLocked
        isTrashed = note.isTrashed
        trashedAt = note.trashedAt
        externalPath = note.externalPath
    }

    func applied(to note: Note) -> Note {
        var copy = note
        copy.createdAt = createdAt
        copy.modifiedAt = modifiedAt
        copy.isPinned = isPinned
        copy.isLocked = isLocked
        copy.isTrashed = isTrashed
        copy.trashedAt = trashedAt
        copy.externalPath = externalPath
        return copy
    }
}

struct LibraryIndex: Codable {
    var version: Int = 1
    var records: [NoteRecord] = []
    var selectedNoteID: UUID?
}
