import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct MishkaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var state: AppState

    init() {
        _settings = StateObject(wrappedValue: AppSettings())
        _state = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        // `Window`, not `WindowGroup`: a note library is one workspace, and a group would
        // spawn a whole new window every time a file is handed over by Finder.
        Window("Mishka", id: "main") {
            RootView()
                .environmentObject(settings)
                .environmentObject(state)
                .onAppear {
                    appDelegate.store = state.store
                    appDelegate.openFilesHandler = { urls in state.openFiles(urls) }
                    let pending = appDelegate.consumePendingURLs()
                    if !pending.isEmpty { state.openFiles(pending) }
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1240, height: 800)
        .commands {
            MishkaCommands(state: state, settings: settings)
        }

        Settings {
            PreferencesView()
                .environmentObject(settings)
                .environmentObject(state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: NoteStore?
    /// Set by the UI so files opened from Finder land in the same code path as ⌘O.
    var openFilesHandler: (([URL]) -> Void)?
    /// A cold start from Finder delivers the URLs before the UI exists; hold them here.
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let openFilesHandler {
            openFilesHandler(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func consumePendingURLs() -> [URL] {
        defer { pendingURLs = [] }
        return pendingURLs
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush the debounced index write so nothing is lost on quit.
        store?.flush()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = nil
    }
}

// MARK: - Menu bar

struct MishkaCommands: Commands {
    @ObservedObject var state: AppState
    @ObservedObject var settings: AppSettings

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { state.newNote() }
                .keyboardShortcut("n", modifiers: .command)

            Button("New Note from Clipboard") {
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                state.store.createNote(initialText: text)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Open Markdown File…") { state.openFilePanel() }
                .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent") {
                if state.recentFilePaths.isEmpty {
                    Button("No Recent Files") {}.disabled(true)
                } else {
                    ForEach(state.recentFilePaths, id: \.self) { path in
                        Button(recentLabel(path)) { state.openRecentFile(path) }
                    }
                    Divider()
                    Button("Clear Menu") { state.clearRecentFiles() }
                }
            }

            Divider()

            Button("Copy Markdown into Library…") { importFiles() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(after: .saveItem) {
            Divider()
            Menu("Export") {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.label) { state.exportCurrentNote(format: format) }
                }
            }
            Button("Reveal Note in Finder") {
                if let note = state.selectedNote { state.store.revealInFinder(id: note.id) }
            }
            Button("Move to Trash") { state.trashSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
        }

        // These land inside the standard Format menu. Adding a second menu of the same
        // name would duplicate it in the menu bar.
        CommandGroup(replacing: .textFormatting) {
            Button("Bold") { send(#selector(MarkdownTextView.toggleBold(_:))) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { send(#selector(MarkdownTextView.toggleItalic(_:))) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Strikethrough") { send(#selector(MarkdownTextView.toggleStrikethrough(_:))) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Highlight") { send(#selector(MarkdownTextView.toggleHighlight(_:))) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Code") { send(#selector(MarkdownTextView.toggleInlineCode(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            Button("Heading 1") { send(#selector(MarkdownTextView.makeHeading1(_:))) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Heading 2") { send(#selector(MarkdownTextView.makeHeading2(_:))) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Heading 3") { send(#selector(MarkdownTextView.makeHeading3(_:))) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Body Text") { send(#selector(MarkdownTextView.makePlainParagraph(_:))) }
                .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Task List") { send(#selector(MarkdownTextView.toggleTaskList(_:))) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Bullet List") { send(#selector(MarkdownTextView.toggleBulletList(_:))) }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Numbered List") { send(#selector(MarkdownTextView.toggleNumberedList(_:))) }
                .keyboardShortcut("9", modifiers: [.command, .shift])
            Button("Block Quote") { send(#selector(MarkdownTextView.toggleQuote(_:))) }
                .keyboardShortcut("'", modifiers: .command)

            Divider()

            Button("Link…") { send(#selector(MarkdownTextView.insertLink(_:))) }
                .keyboardShortcut("k", modifiers: .command)
        }

        // Likewise these extend the standard View menu.
        CommandGroup(after: .toolbar) {
            Button("Editor Only") { settings.editorMode = .editor }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Split View") { settings.editorMode = .split }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Preview Only") { settings.editorMode = .preview }
                .keyboardShortcut("3", modifiers: [.command, .option])

            Divider()

            Button("Toggle Focused Mode") { settings.focusMode.toggle() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Toggle("Show Status Bar", isOn: Binding(
                get: { settings.showWordCount },
                set: { settings.showWordCount = $0 }
            ))

            Divider()

            Button("Next Note") { state.selectNextNote(offset: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous Note") { state.selectNextNote(offset: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

            Divider()

            Button("Find Notes") { state.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Find in Note") {
                NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .help) {
            Button("Mishka Help") {
                if let url = URL(string: "https://bear.app/faq/") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// "Report.md — ~/work/notes" so two files with the same name stay distinguishable.
    private func recentLabel(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let folder = url.deletingLastPathComponent().lastPathComponent
        return folder.isEmpty ? url.lastPathComponent : "\(url.lastPathComponent) — \(folder)"
    }

    private func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText]
        panel.title = "Import Markdown"
        guard panel.runModal() == .OK else { return }
        state.store.importMarkdownFiles(panel.urls)
        state.status("Imported \(panel.urls.count) file\(panel.urls.count == 1 ? "" : "s")")
    }
}
