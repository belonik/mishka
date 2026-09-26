import AppKit
import SwiftUI
import WebKit

/// WKWebView-backed markdown preview.
///
/// The document is loaded once per theme/typography change; every content change after that
/// only replaces `document.body.innerHTML`, which keeps the reader's scroll position.
///
/// The subtle part is that a document load is asynchronous. A note switch can arrive while
/// the previous `loadHTMLString` is still in flight, and that load would finish *after* the
/// content update and silently overwrite it — the preview ends up one note behind. So when a
/// load is pending the newest markdown is parked in `pendingMarkdown` and applied from
/// `didFinish`, where it cannot be clobbered.
struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let theme: Theme
    let fontCSS: String
    let basePath: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(webView)
        context.coordinator.request(markdown: markdown, theme: theme, fontCSS: fontCSS, basePath: basePath)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.request(markdown: markdown, theme: theme, fontCSS: fontCSS, basePath: basePath)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private weak var webView: WKWebView?
        private var loadedSignature: String?
        private var renderedMarkdown: String?
        /// Markdown that arrived while a document load was still running.
        private var pendingMarkdown: String?
        private var currentTheme: Theme = ThemeCatalog.theme(id: ThemeCatalog.defaultID)
        private var currentBasePath: URL?
        private var isReady = false

        func attach(_ webView: WKWebView) {
            self.webView = webView
            isReady = false
        }

        func request(markdown: String, theme: Theme, fontCSS: String, basePath: URL?) {
            guard let webView else { return }
            currentTheme = theme
            currentBasePath = basePath

            let signature = [theme.id, theme.background, theme.text, fontCSS].joined(separator: "|")
            if loadedSignature != signature {
                // Stylesheet or palette changed: a fresh document is required.
                loadedSignature = signature
                renderedMarkdown = markdown
                pendingMarkdown = nil
                isReady = false
                let document = MarkdownRenderer.html(
                    from: markdown,
                    theme: theme,
                    fontCSS: fontCSS,
                    basePath: basePath
                )
                webView.loadHTMLString(document, baseURL: basePath)
                return
            }

            guard renderedMarkdown != markdown else { return }
            guard isReady else {
                // Park it; `didFinish` will apply the newest content once the load settles.
                pendingMarkdown = markdown
                return
            }
            renderedMarkdown = markdown
            apply(markdown: markdown)
        }

        private func apply(markdown: String) {
            guard let webView else { return }
            let body = MarkdownRenderer.bodyHTML(from: markdown, theme: currentTheme, basePath: currentBasePath)
            webView.evaluateJavaScript("document.body.innerHTML = \(Coordinator.javaScriptLiteral(body));")
        }

        /// Serialises a Swift string into a safe JavaScript string literal.
        static func javaScriptLiteral(_ value: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
                  let json = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return String(json.dropFirst().dropLast())
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isReady = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            guard let pending = pendingMarkdown else { return }
            pendingMarkdown = nil
            renderedMarkdown = pending
            apply(markdown: pending)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isReady = true
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Links open in the default browser instead of hijacking the preview pane.
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// Prints / exports the rendered document. Kept separate from the on-screen preview so an
/// export never disturbs what the reader is looking at.
enum PreviewExporter {
    static func pdfData(
        markdown: String,
        theme: Theme,
        fontCSS: String,
        basePath: URL?,
        completion: @escaping (Data?) -> Void
    ) {
        let document = MarkdownRenderer.html(from: markdown, theme: theme, fontCSS: fontCSS, basePath: basePath)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123))
        let delegate = ExportNavigationDelegate { success in
            if success {
                let configuration = WKPDFConfiguration()
                webView.createPDF(configuration: configuration) { result in
                    switch result {
                    case .success(let data): completion(data)
                    case .failure: completion(nil)
                    }
                }
            } else {
                completion(nil)
            }
        }
        objc_setAssociatedObject(webView, &ExportNavigationDelegate.associationKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(document, baseURL: basePath)
    }

    private final class ExportNavigationDelegate: NSObject, WKNavigationDelegate {
        static var associationKey: UInt8 = 0
        private let completion: (Bool) -> Void
        private var finished = false

        init(completion: @escaping (Bool) -> Void) {
            self.completion = completion
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !finished else { return }
            finished = true
            // Give WebKit a moment to lay the document out before paginating.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [completion] in
                completion(true)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !finished else { return }
            finished = true
            completion(false)
        }
    }
}
