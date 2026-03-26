import SwiftUI
import WebKit

/// Renders a Mermaid diagram source string as a visual diagram via WKWebView + mermaid.js.
/// Auto-sizes to fit the rendered diagram height.
struct MermaidDiagramView: NSViewRepresentable {
    let source: String
    @Binding var measuredHeight: CGFloat

    init(source: String, measuredHeight: Binding<CGFloat>) {
        self.source = source
        self._measuredHeight = measuredHeight
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityIdentifier("mermaidDiagram.webView")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
        <style>
            * { box-sizing: border-box; }
            html, body {
                margin: 0; padding: 0;
                background: transparent;
            }
            body {
                padding: 12px;
                display: flex;
                justify-content: center;
                align-items: flex-start;
            }
            #diagram {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            }
            #diagram svg {
                max-width: 100%;
                height: auto;
                display: block;
            }
            .error-msg {
                color: #ff6b6b;
                font-family: -apple-system, sans-serif;
                font-size: 12px;
                padding: 8px;
            }
        </style>
        </head>
        <body>
        <div class="mermaid" id="diagram">
        \(escaped)
        </div>
        <script>
            mermaid.initialize({
                startOnLoad: true,
                theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default',
                securityLevel: 'strict',
                fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
                fontSize: 13
            });

            function reportHeight() {
                // Try SVG element first (most accurate after render)
                const svg = document.querySelector('#diagram svg');
                if (svg) {
                    const rect = svg.getBoundingClientRect();
                    const h = Math.ceil(rect.height) + 24; // + body padding
                    window.webkit.messageHandlers.heightChanged.postMessage(h);
                    return;
                }
                // Fallback to body
                const h = document.body.scrollHeight;
                if (h > 0) {
                    window.webkit.messageHandlers.heightChanged.postMessage(h);
                }
            }
            // Mermaid renders async — poll until SVG appears
            let attempts = 0;
            const poll = setInterval(() => {
                attempts++;
                reportHeight();
                if (document.querySelector('#diagram svg') || attempts > 20) {
                    clearInterval(poll);
                }
            }, 250);
            new MutationObserver(reportHeight).observe(
                document.getElementById('diagram'),
                { childList: true, subtree: true }
            );
        </script>
        </body>
        </html>
        """

        if context.coordinator.lastSource != source {
            context.coordinator.lastSource = source
            context.coordinator.heightBinding = $measuredHeight
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastSource: String?
        var heightBinding: Binding<CGFloat>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "heightChanged")
            webView.configuration.userContentController.add(self, name: "heightChanged")
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
