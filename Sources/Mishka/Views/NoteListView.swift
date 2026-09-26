import SwiftUI

/// Middle column: search, sort and the list of notes for the current sidebar selection.
struct NoteListView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings

    private var theme: Theme { settings.theme }
    private var accent: Color { settings.accent }
    private var notes: [Note] { state.visibleNotes }
    private var isTrash: Bool { state.sidebarSelection == .trash }
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color(hex: theme.border).opacity(0.8))
                .frame(height: 1)

            if notes.isEmpty {
                emptyState
            } else {
                noteList
            }
        }
        .background(Color(hex: theme.list))
        .onChange(of: state.searchFocusToken) { _, _ in
            searchFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: theme.text))
                    .lineLimit(1)

                Spacer(minLength: 4)

                IconButton(
                    symbol: "arrow.up.arrow.down",
                    theme: theme,
                    help: "Sort notes"
                ) {}
                .overlay(sortMenu)
                .frame(width: 26, height: 22)

                IconButton(symbol: "square.and.pencil", theme: theme, help: "New note (⌘N)") {
                    state.newNote()
                }
            }

            if isTrash {
                HStack(spacing: 6) {
                    Text("Notes in trash are kept until you empty it")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(hex: theme.tertiaryText))
                    Spacer()
                    Button("Empty") { state.store.emptyTrash() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(accent)
                }
            } else {
                SearchField(
                    text: $state.searchQuery,
                    theme: theme,
                    accent: accent,
                    isFocused: $searchFocused
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 8)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortField.allCases) { field in
                Button {
                    settings.sortField = field
                    state.refreshSortOrder(settings.sortOrder)
                } label: {
                    HStack {
                        Text(field.label)
                        if settings.sortField == field { Image(systemName: "checkmark") }
                    }
                }
            }
            Divider()
            Button(settings.sortAscending ? "Ascending ↑" : "Descending ↓") {
                settings.sortAscending.toggle()
                state.refreshSortOrder(settings.sortOrder)
            }
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 22)
        .opacity(0.001)
    }

    private var title: String {
        switch state.sidebarSelection {
        case .all: return "All Notes"
        case .pinned: return "Pinned"
        case .files: return "Files"
        case .untagged: return "Untagged"
        case .todo: return "To-do"
        case .today: return "Today"
        case .locked: return "Locked"
        case .trash: return "Trash"
        case .tag(let path): return "#" + path
        }
    }

    // MARK: - List

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(notes) { note in
                    // A real button rather than a tap gesture: it hit-tests reliably on
                    // macOS, works with the keyboard and is what VoiceOver expects.
                    Button {
                        state.select(note)
                    } label: {
                        NoteRow(
                            note: note,
                            isSelected: state.store.selectedNoteID == note.id,
                            query: state.searchQuery,
                            theme: theme,
                            accent: accent
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextMenu(for: note) }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .scrollContentBackground(.hidden)
    }

    private var emptySubtitle: String {
        switch state.sidebarSelection {
        case .trash: return "Deleted notes will appear here."
        case .files: return "Press ⌘O to open a markdown file where it lives."
        default: return "Press ⌘N to write your first note."
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            symbol: state.searchQuery.isEmpty ? "tray" : "magnifyingglass",
            title: state.searchQuery.isEmpty ? "No notes here" : "Nothing found",
            subtitle: state.searchQuery.isEmpty
                ? emptySubtitle
                : "No note matches “\(state.searchQuery)”.",
            theme: theme,
            accent: accent
        )
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for note: Note) -> some View {
        if isTrash {
            Button("Restore") { state.store.restore(id: note.id) }
            Button("Delete Permanently") { state.store.deletePermanently(id: note.id) }
        } else {
            Button(note.isPinned ? "Unpin" : "Pin") { state.store.togglePinned(id: note.id) }
            Button(note.isLocked ? "Unlock" : "Lock") { state.store.setLocked(!note.isLocked, id: note.id) }
            Button("Duplicate") { state.store.duplicate(id: note.id) }
            Divider()
            Button("Copy as Markdown") {
                Exporter.copyToPasteboard(note: note, asHTML: false, settings: settings)
                state.status("Copied as Markdown")
            }
            Button("Copy as HTML") {
                Exporter.copyToPasteboard(note: note, asHTML: true, settings: settings)
                state.status("Copied as HTML")
            }
            Menu("Export") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.label) {
                        Exporter.export(note: note, format: format, settings: settings) { state.status($0) }
                    }
                }
            }
            Divider()
            Button("Reveal in Finder") { state.store.revealInFinder(id: note.id) }
            if note.isExternal {
                Divider()
                Button("Remove from Mishka") { state.forget(note: note) }
            } else {
                Button("Move to Trash") { state.store.moveToTrash(id: note.id) }
            }
        }
    }
}

/// One row of the note list.
struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let query: String
    let theme: Theme
    let accent: Color

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(accent.opacity(0.9))
                        .rotationEffect(.degrees(35))
                }
                if note.isExternal {
                    Image(systemName: note.isMissing ? "exclamationmark.triangle.fill" : "doc.text")
                        .font(.system(size: 8.5))
                        .foregroundStyle(note.isMissing
                            ? Color.orange.opacity(0.95)
                            : Color(hex: theme.tertiaryText))
                        .help(note.isMissing
                            ? "File not found: \(note.externalPath ?? "")"
                            : (note.externalPath ?? ""))
                }
                highlightedTitle
                Spacer(minLength: 4)
                Text(DateFormat.short(note.modifiedAt))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(hex: theme.tertiaryText))
                    .fixedSize()
            }

            if !note.snippet.isEmpty {
                Text(note.snippet)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hex: theme.secondaryText))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !note.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(note.tags.prefix(3), id: \.self) { tag in
                        TagChip(tag: tag, theme: theme, accent: accent)
                    }
                    if note.tags.count > 3 {
                        Text("+\(note.tags.count - 3)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: theme.tertiaryText))
                    }
                    if note.hasOpenTask {
                        Image(systemName: "checklist")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: theme.tertiaryText))
                    }
                }
                .padding(.top, 1)
            } else if note.hasOpenTask {
                Image(systemName: "checklist")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(hex: theme.tertiaryText))
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isSelected)
    }

    private var background: Color {
        if isSelected { return accent.opacity(theme.isDark ? 0.24 : 0.15) }
        if isHovering { return Color(hex: theme.text).opacity(0.045) }
        return .clear
    }

    /// Title with the search term picked out, Bear-style.
    private var highlightedTitle: some View {
        Group {
            if query.isEmpty {
                Text(note.title)
            } else {
                Text(Self.attributed(note.title, query: query, accent: accent))
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color(hex: theme.text))
        .lineLimit(1)
    }

    static func attributed(_ text: String, query: String, accent: Color) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<text.endIndex) {
            if let lower = AttributedString.Index(found.lowerBound, within: result),
               let upper = AttributedString.Index(found.upperBound, within: result) {
                result[lower..<upper].foregroundColor = accent
                result[lower..<upper].backgroundColor = accent.opacity(0.16)
            }
            searchStart = found.upperBound
        }
        return result
    }
}
