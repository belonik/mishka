// Offscreen renderer used while developing the look of the editor and the preview.
//
//   swiftc -module-cache-path .dsh-modulecache \
//     Sources/Mishka/Support/Utilities.swift \
//     Sources/Mishka/Models/Note.swift Sources/Mishka/Models/Tag.swift \
//     Sources/Mishka/Theme/Theme.swift Sources/Mishka/Theme/ThemeCatalog.swift \
//     Sources/Mishka/Markdown/MarkdownRenderer.swift \
//     Sources/Mishka/Editor/MarkdownHighlighter.swift \
//     Sources/Mishka/Editor/MarkdownTextView.swift \
//     Sources/Mishka/Views/PreviewPane.swift \
//     Tools/render-samples.swift -o /tmp/render-samples
//
// It is NOT part of the app target: it only exists to eyeball typography without
// launching the GUI. Writes /tmp/mishka-preview.png and /tmp/mishka-editor.png.

import AppKit
import WebKit

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"

let sample = """
---
type: quarter
owner: Продукт
status: active
---
# Квартальный отчёт

Короткая заметка с таблицей, списком и кодом.

## Метрики

| Направление | План | Факт | Δ | Статус |
| --- | ---: | ---: | ---: | :---: |
| Интервью | 24 | 0 | −24 | 🔴 |
| Демо | 12 | 3 | −9 | 🟡 |
| Пилоты | 4 | 1 | −3 | 🟢 |
| Выручка, млн ₽ | 18.5 | 4.2 | −14.3 | 🔴 |

Обычный абзац после таблицы, чтобы видеть отступы.

- [x] Собрать цифры
- [ ] Согласовать с командой

| Параметр | Значение |
| --- | --- |
| Владелец | Продукт |
| Срок | 13.12.2026 |

Широкая таблица — должна остаться в границах страницы и прокручиваться:

| Направление | Ответственный | План | Факт | Δ | Комментарий | Следующий шаг | Дата |
| --- | --- | ---: | ---: | ---: | --- | --- | --- |
| Коммерческие касания | Команда A | 5 | 2 | −3 | Часть писем без ответа | Дожать тёплые контакты | 27.09 |
| Интервью | Продукт | 2 | 0 | −2 | Календарь не собран | Забронировать слоты | 04.10 |

> Цитата для контраста.

```swift
let x = 1  // **не жирный**
```
"""

// MARK: - Helpers

func writePNG(_ image: NSImage, to path: String) -> Bool {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { return false }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        return false
    }
}

func writeRep(_ rep: NSBitmapImageRep, to path: String) -> Bool {
    guard let data = rep.representation(using: .png, properties: [:]) else { return false }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        return false
    }
}

// MARK: - Editor snapshot

func renderEditor(theme: Theme, accent: NSColor, width: CGFloat, height: CGFloat) -> NSBitmapImageRep? {
    let typography = EditorTypography(family: .system, size: 15, lineSpacing: 4.5, paragraphSpacing: 9)
    let textView = MarkdownTextView(theme: theme, accent: accent, typography: typography)
    textView.maxContentWidth = 720

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    scrollView.hasVerticalScroller = false
    scrollView.documentView = textView
    textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    window.contentView = scrollView
    window.orderBack(nil)

    textView.string = sample
    textView.setSelectedRange(NSRange(location: (sample as NSString).length, length: 0), affinity: .downstream, stillSelecting: false)
    textView.refreshHighlight()

    // Let AppKit run one layout pass before rasterising.
    window.displayIfNeeded()
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)

    guard let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else { return nil }
    textView.cacheDisplay(in: textView.bounds, to: rep)
    return rep
}

// MARK: - Preview snapshot

final class PreviewSnapshotter: NSObject, WKNavigationDelegate {
    private let theme: Theme
    private let fontCSS: String
    private let outputDirectory: String
    private let done: () -> Void

    init(theme: Theme, fontCSS: String, outputDirectory: String, done: @escaping () -> Void) {
        self.theme = theme
        self.fontCSS = fontCSS
        self.outputDirectory = outputDirectory
        self.done = done
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            webView.takeSnapshot(with: configuration) { image, error in
                if let image, writePNG(image, to: self.outputDirectory + "/mishka-preview.png") {
                    print("preview → \(self.outputDirectory)/mishka-preview.png")
                } else {
                    print("preview snapshot failed: \(String(describing: error))")
                }
                self.done()
            }
        }
    }
}

// MARK: - Run

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let theme = ThemeCatalog.theme(id: "mishka-light")
let accent = NSColor(hex: AccentCatalog.all[0].hex)

for (name, id) in [("editor", "mishka-light"), ("editor-dark", "mishka-dark")] {
    let themeForEditor = ThemeCatalog.theme(id: id)
    if let rep = renderEditor(theme: themeForEditor, accent: accent, width: 760, height: 1000) {
        print("\(name) → \(outputDirectory)/mishka-\(name).png : \(writeRep(rep, to: outputDirectory + "/mishka-\(name).png"))")
    } else {
        print("\(name) render failed")
    }
}

let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1150))
let document = MarkdownRenderer.html(from: sample, theme: theme, fontCSS: "font-family: -apple-system, sans-serif; font-size: 15px;", basePath: nil)
let snapshotter = PreviewSnapshotter(theme: theme, fontCSS: "", outputDirectory: outputDirectory) {
    exit(0)
}
webView.navigationDelegate = snapshotter
webView.loadHTMLString(document, baseURL: nil)

DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
    print("preview timed out")
    exit(1)
}
app.run()
