import AppKit
import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case html
    case pdf

    var id: String { rawValue }

    var label: String {
        switch self {
        case .markdown: return "Markdown (.md)"
        case .html: return "Web Page (.html)"
        case .pdf: return "PDF (.pdf)"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .html: return "html"
        case .pdf: return "pdf"
        }
    }
}

enum Exporter {

    /// Saves the note in the requested format. `settings` is only needed for the themed
    /// HTML/PDF output; markdown export is always plain text.
    static func export(
        note: Note,
        format: ExportFormat,
        settings: AppSettings?,
        completion: @escaping (String) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(note.title).\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export “\(note.title)”"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        switch format {
        case .markdown:
            write(note.text, to: url, completion: completion)

        case .html:
            let theme = settings?.theme ?? ThemeCatalog.theme(id: ThemeCatalog.defaultID)
            let fontCSS = settings?.previewFontCSS ?? "font-size: 15px;"
            let html = MarkdownRenderer.html(
                from: note.text,
                theme: theme,
                fontCSS: fontCSS,
                basePath: nil
            )
            write(html, to: url, completion: completion)

        case .pdf:
            let theme = settings?.theme ?? ThemeCatalog.theme(id: ThemeCatalog.defaultID)
            let fontCSS = settings?.previewFontCSS ?? "font-size: 15px;"
            PreviewExporter.pdfData(markdown: note.text, theme: theme, fontCSS: fontCSS, basePath: nil) { data in
                guard let data else {
                    completion("PDF export failed")
                    return
                }
                do {
                    try data.write(to: url, options: .atomic)
                    completion("Exported “\(note.title).pdf”")
                } catch {
                    completion("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    static func copyToPasteboard(note: Note, asHTML: Bool, settings: AppSettings?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if asHTML {
            let theme = settings?.theme ?? ThemeCatalog.theme(id: ThemeCatalog.defaultID)
            let html = MarkdownRenderer.bodyHTML(from: note.text, theme: theme, basePath: nil)
            pasteboard.setString(html, forType: .html)
            pasteboard.setString(note.text, forType: .string)
        } else {
            pasteboard.setString(note.text, forType: .string)
        }
    }

    private static func write(_ contents: String, to url: URL, completion: @escaping (String) -> Void) {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            completion("Exported “\(url.lastPathComponent)”")
        } catch {
            completion("Export failed: \(error.localizedDescription)")
        }
    }
}
