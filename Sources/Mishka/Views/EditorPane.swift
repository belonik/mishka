import AppKit
import SwiftUI

/// The right-hand column: the live markdown editor, the preview, or both side by side,
/// with a Bear-like status bar underneath.
struct EditorPane: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: AppSettings
    let note: Note

    private var theme: Theme { settings.theme }
    private var accent: Color { settings.accent }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch settings.editorMode {
                case .editor:
                    editor
                case .preview:
                    preview
                case .split:
                    HStack(spacing: 0) {
                        editor
                        ThemedDivider(theme: theme)
                        preview
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if settings.showWordCount {
                StatusBar(note: note, theme: theme, onReveal: {
                    state.store.revealInFinder(id: note.id)
                })
            }
        }
        .background(Color(hex: theme.background))
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                if note.isMissing {
                    missingFileBanner
                }
                if note.isLocked {
                    lockedBanner
                }
            }
        }
    }

    // MARK: - Panes

    private var editor: some View {
        MarkdownEditor(
            noteID: note.id,
            text: note.text,
            theme: theme,
            accentHex: settings.accentHex,
            typography: settings.typography,
            focusMode: settings.focusMode,
            maxContentWidth: CGFloat(settings.maxContentWidth),
            isEditable: !note.isLocked,
            spellChecking: settings.spellChecking,
            onChange: { newText in
                state.store.update(id: note.id, text: newText)
            },
            onSelectionChange: { _ in },
            onToggleTask: { _ in }
        )
        .id("mishka-editor")
        .background(Color(hex: theme.background))
    }

    private var preview: some View {
        MarkdownPreviewView(
            markdown: note.text,
            theme: theme,
            fontCSS: settings.previewFontCSS,
            basePath: state.store.fileURL(for: note).deletingLastPathComponent()
        )
        .id("mishka-preview")
        .background(Color(hex: theme.background))
    }

    /// A bound file can vanish between launches; say so plainly and offer a way out.
    private var missingFileBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("File not found")
                    .font(.system(size: 12, weight: .medium))
                Text(note.externalPath ?? "")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(hex: theme.tertiaryText))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let path = note.externalPath {
                Button("Find Again…") {
                    relocate(path: path)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
            }
            Button("Remove") { state.forget(note: note) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
        }
        .foregroundStyle(Color(hex: theme.secondaryText))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: theme.border)).frame(height: 1)
        }
    }

    /// Points the note at a file the user picks, keeping its history entry.
    private func relocate(path: String) {
        let panel = NSOpenPanel()
        panel.title = "Locate “\((path as NSString).lastPathComponent)”"
        panel.prompt = "Use This File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.store.forget(id: note.id)
        state.openFiles([url])
    }

    private var lockedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
            Text("This note is locked")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Unlock") {
                state.store.setLocked(false, id: note.id)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accent)
        }
        .foregroundStyle(Color(hex: theme.secondaryText))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: theme.border)).frame(height: 1)
        }
    }
}

/// Slim info strip at the bottom of the editor.
struct StatusBar: View {
    let note: Note
    let theme: Theme
    var onReveal: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let path = note.externalPath {
                Button {
                    onReveal?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9.5))
                        Text(note.externalFileName ?? path)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(hex: theme.secondaryText))
                }
                .buttonStyle(.plain)
                .help("Editing in place — \(path)")
            }

            Text(Date2.relative(note.modifiedAt))
                .font(.system(size: 10.5))
                .foregroundStyle(Color(hex: theme.tertiaryText))

            Spacer(minLength: 8)

            if !note.tags.isEmpty {
                Text("\(note.tags.count) tag\(note.tags.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(hex: theme.tertiaryText))
            }

            Text("\(note.text.wordCount) words")
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(Color(hex: theme.tertiaryText))

            Text("\(note.text.characterCount) characters")
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(Color(hex: theme.tertiaryText))

            if note.text.readingMinutes > 0 {
                Text("\(note.text.readingMinutes) min read")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: theme.tertiaryText))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Color(hex: theme.background))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(hex: theme.border).opacity(0.7)).frame(height: 1)
        }
    }
}

/// Tiny shim so the status bar reads nicely without repeating formatter setup.
private enum Date2 {
    static func relative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Edited just now" }
        return "Edited " + DateFormat.relative(date)
    }
}
