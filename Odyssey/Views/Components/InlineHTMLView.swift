import SwiftUI
import WebKit

/// Sandboxed WKWebView for rendering HTML content inline in chat messages.
/// Auto-sizes to fit content height, no internal scrolling.
struct InlineHTMLView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    @Binding var measuredHeight: CGFloat

    init(html: String, baseURL: URL? = nil, measuredHeight: Binding<CGFloat>) {
        self.html = html
        self.baseURL = baseURL
        self._measuredHeight = measuredHeight
    }

    /// Load HTML from a local file path.
    init(filePath: String, measuredHeight: Binding<CGFloat>) {
        let url = URL(fileURLWithPath: filePath)
        self.html = (try? String(contentsOf: url, encoding: .utf8)) ?? "<p>Failed to load file</p>"
        self.baseURL = url.deletingLastPathComponent()
        self._measuredHeight = measuredHeight
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityIdentifier("inlineHTML.webView")
        // Disable WebView's own scrolling — parent ScrollView handles it
        webView.enclosingScrollView?.hasVerticalScroller = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let wrapped = wrapInDocument(html)
        if context.coordinator.lastHTML != wrapped {
            context.coordinator.lastHTML = wrapped
            context.coordinator.heightBinding = $measuredHeight
            webView.loadHTMLString(wrapped, baseURL: baseURL)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Wrap raw HTML in a minimal document with dark-mode-aware styling and height reporting.
    private func wrapInDocument(_ content: String) -> String {
        if content.lowercased().contains("<html") || content.lowercased().contains("<!doctype") {
            return content
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            * { box-sizing: border-box; }
            html, body {
                margin: 0; padding: 0;
                overflow: hidden;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 13px;
                color: #e0e0e0;
                background: transparent;
            }
            body { padding: 10px; }
            @media (prefers-color-scheme: light) {
                body { color: #1a1a1a; }
            }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid rgba(128,128,128,0.3); padding: 6px 10px; text-align: left; }
            th { font-weight: 600; }
            img { max-width: 100%; border-radius: 6px; }
            pre { background: rgba(128,128,128,0.1); padding: 8px; border-radius: 6px; overflow-x: auto; }
            code { font-family: ui-monospace, monospace; font-size: 12px; }
        </style>
        </head>
        <body>\(content)</body>
        <script>
            function reportHeight() {
                const h = document.body.scrollHeight;
                window.webkit.messageHandlers.heightChanged.postMessage(h);
            }
            window.addEventListener('load', reportHeight);
            new ResizeObserver(reportHeight).observe(document.body);
        </script>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML: String?
        var heightBinding: Binding<CGFloat>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Register message handler for height reports
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightChanged")
            webView.configuration.userContentController.add(self, name: "heightChanged")

            // Fallback: measure height via JS after load
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                if let h = result as? CGFloat, h > 0 {
                    DispatchQueue.main.async {
                        self?.heightBinding?.wrappedValue = h
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightChanged", let h = message.body as? CGFloat, h > 0 {
                DispatchQueue.main.async {
                    self.heightBinding?.wrappedValue = h
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .other {
                return .allow
            }
            return .cancel
        }
    }
}

/// Container that wraps InlineHTMLView with a card-like appearance and "Open in Browser" action.
struct InlineHTMLCard: View {
    let title: String?
    let html: String
    let filePath: String?
    let maxHeight: CGFloat

    @State private var isExpanded = true
    @State private var contentHeight: CGFloat = 100

    init(title: String? = nil, html: String = "", filePath: String? = nil, maxHeight: CGFloat = 600) {
        self.title = title
        self.html = html
        self.filePath = filePath
        self.maxHeight = maxHeight
    }

    private var displayHeight: CGFloat {
        min(contentHeight, maxHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().opacity(0.3)
                if let filePath {
                    InlineHTMLView(filePath: filePath, measuredHeight: $contentHeight)
                        .frame(height: displayHeight)
                } else {
                    InlineHTMLView(html: html, measuredHeight: $contentHeight)
                        .frame(height: displayHeight)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
        .xrayId("inlineHTMLCard.container")
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .foregroundStyle(.blue)
                        .font(.caption)

                    Text(title ?? fileName ?? "HTML Content")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Button {
                openInBrowser()
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in browser")
            .xrayId("inlineHTMLCard.openInBrowser")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.textBackgroundColor).opacity(0.4))
        .xrayId("inlineHTMLCard.header")
    }

    private var fileName: String? {
        guard let path = filePath else { return nil }
        return (path as NSString).lastPathComponent
    }

    private func openInBrowser() {
        let content: String
        if let filePath {
            content = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? html
        } else {
            content = html
        }
        RichContentOpener.openHTML(content, title: title)
    }
}

// MARK: - Shared utility for opening rich content in browser

enum RichContentOpener {
    static func openHTML(_ html: String, title: String? = nil) {
        let doc: String
        if html.lowercased().contains("<html") || html.lowercased().contains("<!doctype") {
            doc = html
        } else {
            doc = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <title>\(title ?? "Rich Content")</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    max-width: 900px; margin: 40px auto; padding: 0 20px;
                    color: #1a1a1a; background: #fff;
                }
                @media (prefers-color-scheme: dark) {
                    body { color: #e0e0e0; background: #1e1e1e; }
                }
                table { border-collapse: collapse; width: 100%; }
                th, td { border: 1px solid rgba(128,128,128,0.3); padding: 8px 12px; text-align: left; }
                th { font-weight: 600; }
                img { max-width: 100%; border-radius: 8px; }
                pre { background: rgba(128,128,128,0.1); padding: 12px; border-radius: 8px; overflow-x: auto; }
                code { font-family: ui-monospace, monospace; }
            </style>
            </head>
            <body>\(html)</body>
            </html>
            """
        }
        writeTempAndOpen(doc, ext: "html")
    }

    static func openMermaid(_ source: String, title: String? = nil) {
        let doc = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(title ?? "Diagram")</title>
        <style>
            body {
                display: flex; justify-content: center; align-items: center;
                min-height: 100vh; margin: 0; padding: 20px;
                background: #fff;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            }
            @media (prefers-color-scheme: dark) {
                body { background: #1e1e1e; }
            }
            .mermaid { max-width: 100%; }
        </style>
        <script type="module">
            import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
            mermaid.initialize({ startOnLoad: true, theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default' });
        </script>
        </head>
        <body>
        <pre class="mermaid">
        \(source)
        </pre>
        </body>
        </html>
        """
        writeTempAndOpen(doc, ext: "html")
    }

    private static func writeTempAndOpen(_ content: String, ext: String) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("odyssey-\(UUID().uuidString.prefix(8)).\(ext)")
        try? content.write(to: tmp, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(tmp)
    }
}
