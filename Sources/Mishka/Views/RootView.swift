import SwiftUI
import UniformTypeIdentifiers

/// Three columns, Bear-style: tags on the left, the note list in the middle, the editor on
/// the right. The dividers between them are draggable.
struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { settings.theme }
    private var accent: Color { settings.accent }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: settings.sidebarWidth)

            ResizableDivider(
                width: $settings.sidebarWidth,
                range: 180...340,
                color: Color(hex: theme.border)
            )

            NoteListView()
                .frame(width: settings.listWidth)

            ResizableDivider(
                width: $settings.listWidth,
                range: 240...520,
                color: Color(hex: theme.border)
            )

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 940, minHeight: 560)
        .background(Color(hex: theme.background))
        // EXPERIMENT: preferredColorScheme removed
        .toolbar { toolbarContent }
        .toolbarBackground(Color(hex: theme.sidebar), for: .windowToolbar)
        .onAppear {
            settings.updateSystemAppearance(isDark: colorScheme == .dark)
            state.refreshSortOrder(settings.sortOrder)
            let removed = state.store.purgeTrash(olderThan: settings.trashRetentionDays)
            if removed > 0 {
                state.status("Removed \(removed) old note\(removed == 1 ? "" : "s") from the trash")
            }
        }
        .onChange(of: colorScheme) { _, newValue in
            settings.updateSystemAppearance(isDark: newValue == .dark)
        }
        .onChange(of: settings.sortField) { _, _ in state.refreshSortOrder(settings.sortOrder) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshExternalNotes()
        }
        .onChange(of: settings.sortAscending) { _, _ in state.refreshSortOrder(settings.sortOrder) }
        .overlay(alignment: .bottom) { toast }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            importDropped(providers)
        }
    }

    /// Dropping `.md` files opens them where they lie — the same as File ▸ Open.
    /// Use File ▸ Copy into Library when a copy is actually wanted.
    private func importDropped(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { state.openFiles([url]) }
            }
        }
        return handled
    }

    @ViewBuilder
    private var detail: some View {
        if let note = state.selectedNote {
            EditorPane(note: note)
        } else {
            EmptyStateView(
                symbol: "pawprint",
                title: "Mishka",
                subtitle: "Select a note on the left, or press ⌘N to start writing.",
                theme: theme,
                accent: accent
            )
            .background(Color(hex: theme.background))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                state.newNote()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New note (⌘N)")

            if let note = state.selectedNote {
                Button {
                    state.store.togglePinned(id: note.id)
                } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                }
                .help(note.isPinned ? "Unpin note" : "Pin note")
            }
        }

        ToolbarItemGroup(placement: .principal) {
            Picker("", selection: $settings.editorMode) {
                ForEach(EditorMode.allCases) { mode in
                    Image(systemName: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
            .help("Editor, split or preview")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                settings.focusMode.toggle()
            } label: {
                Image(systemName: settings.focusMode ? "circle.lefthalf.filled.inverse" : "circle.lefthalf.filled")
            }
            .help("Focused mode")

            if let note = state.selectedNote {
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.label) {
                            Exporter.export(note: note, format: format, settings: settings) { state.status($0) }
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26)
                .help("Export note")

                Button {
                    state.trashSelected()
                } label: {
                    Image(systemName: note.isExternal ? "rectangle.badge.minus" : "trash")
                }
                .help(note.isExternal ? "Remove from Mishka (the file stays)" : "Move to trash (⌘⌫)")
            }
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let message = state.statusMessage {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: theme.text))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule().strokeBorder(Color(hex: theme.border), lineWidth: 1)
                )
                .padding(.bottom, 34)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.2), value: message)
        }
    }
}
