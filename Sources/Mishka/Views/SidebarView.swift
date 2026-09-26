import SwiftUI

/// Left column: the fixed smart groups and the nested tag tree.
struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings

    private var theme: Theme { settings.theme }
    private var accent: Color { settings.accent }

    var body: some View {
        VStack(spacing: 0) {
            brand
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    SidebarSectionHeader(title: "Notes", theme: theme)
                    ForEach(smartGroups, id: \.item) { group in
                        SidebarRow(
                            title: group.title,
                            symbol: group.symbol,
                            count: state.sidebarCounts[group.item] ?? 0,
                            isSelected: state.sidebarSelection == group.item,
                            theme: theme,
                            accent: accent
                        )
                        .onTapGesture { state.select(group.item) }
                    }

                    if !state.store.tagTree.isEmpty {
                        SidebarSectionHeader(title: "Tags", theme: theme)
                        ForEach(flatTagRows, id: \.node.id) { row in
                            SidebarRow(
                                title: row.node.displayName,
                                symbol: row.depth == 0 ? "number" : "tag",
                                count: row.node.count,
                                isSelected: state.sidebarSelection == .tag(row.node.id),
                                theme: theme,
                                accent: accent,
                                indent: CGFloat(row.depth) * 11,
                                hasChildren: !row.node.children.isEmpty,
                                isExpanded: state.expandedTags.contains(row.node.id),
                                onToggleExpand: { state.toggleTagExpansion(row.node.id) }
                            )
                            .onTapGesture { state.select(.tag(row.node.id)) }
                            .contextMenu {
                                Button("Rename Tag…") { renameTag(row.node.id) }
                                Button("Delete Tag") { state.store.deleteTag(row.node.id) }
                                Divider()
                                Button("Copy Tag") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString("#" + row.node.id, forType: .string)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.bottom, 12)
            }

            footer
        }
        .background(Color(hex: theme.sidebar))
    }

    // MARK: - Pieces

    private var brand: some View {
        HStack(spacing: 7) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
            Text("Mishka")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: theme.text))
            Spacer()
            IconButton(symbol: "plus", theme: theme, help: "New note (⌘N)") {
                state.newNote()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(hex: theme.border).opacity(0.7))
                .frame(height: 1)
            HStack(spacing: 4) {
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(hex: theme.secondaryText))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")

                IconButton(symbol: "folder", theme: theme, help: "Reveal notes folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([state.store.rootURL])
                }

                IconButton(symbol: "doc.badge.plus", theme: theme, help: "Open a markdown file in place (⌘O)") {
                    state.openFilePanel()
                }

                IconButton(symbol: "arrow.clockwise", theme: theme, help: "Reload from disk") {
                    state.store.reloadFromDisk()
                    state.status("Reloaded from disk")
                }

                Spacer()

                Text("\(state.store.activeNotes.count)")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: theme.tertiaryText))
                    .padding(.trailing, 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    // MARK: - Data

    private struct SmartGroup {
        let item: SidebarItem
        let title: String
        let symbol: String
    }

    private var smartGroups: [SmartGroup] {
        [
            SmartGroup(item: .all, title: "All Notes", symbol: "tray.full"),
            SmartGroup(item: .pinned, title: "Pinned", symbol: "pin"),
            SmartGroup(item: .files, title: "Files", symbol: "doc.text"),
            SmartGroup(item: .todo, title: "To-do", symbol: "checklist"),
            SmartGroup(item: .today, title: "Today", symbol: "clock"),
            SmartGroup(item: .untagged, title: "Untagged", symbol: "tag.slash"),
            SmartGroup(item: .locked, title: "Locked", symbol: "lock"),
            SmartGroup(item: .trash, title: "Trash", symbol: "trash"),
        ]
    }

    private var flatTagRows: [(node: TagNode, depth: Int)] {
        var rows: [(TagNode, Int)] = []
        func walk(_ nodes: [TagNode], _ depth: Int) {
            for node in nodes {
                rows.append((node, depth))
                if state.expandedTags.contains(node.id) {
                    walk(node.children, depth + 1)
                }
            }
        }
        walk(state.store.tagTree, 0)
        return rows.map { (node: $0.0, depth: $0.1) }
    }

    private func renameTag(_ tag: String) {
        let alert = NSAlert()
        alert.messageText = "Rename tag"
        alert.informativeText = "Every note tagged #\(tag) will be updated, including nested tags."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = tag
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.store.renameTag(from: tag, to: field.stringValue)
        state.status("Tag renamed")
    }
}
