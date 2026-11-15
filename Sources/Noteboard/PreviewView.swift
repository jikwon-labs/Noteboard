import AppKit
import WebKit
import NoteboardCore

/// MD 미리보기. 스크립트는 끄고, 링크는 기본 브라우저로 연다.
final class PreviewView: NSView, WKNavigationDelegate {
    private let webView: WKWebView

    override init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: frame)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = Theme.background
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    func show(markdown: String, fontSize: CGFloat) {
        webView.loadHTMLString(Self.page(body: MarkdownHTML.render(markdown), fontSize: fontSize), baseURL: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    static func page(body: String, fontSize: CGFloat) -> String {
        let size = Int(fontSize.rounded())
        return """
        <!doctype html><html lang="ko"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src https: data:">
        <style>
        :root { color-scheme: dark; }
        html, body { margin: 0; background: #1B1B1D; }
        body { padding: 8px 20px 20px; color: #E6E6E8; font: \(size)px/1.55 -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif; -webkit-font-smoothing: antialiased; word-wrap: break-word; }
        h1, h2, h3, h4, h5, h6 { color: #F5F5F7; margin: 0.6em 0 0.3em; line-height: 1.3; }
        h1 { font-size: 1.25em; } h2 { font-size: 1.12em; } h3, h4, h5, h6 { font-size: 1em; }
        body > :first-child { margin-top: 0.2em; }
        p { margin: 0.35em 0; }
        ul, ol { margin: 0.3em 0; padding-left: 1.3em; }
        li { margin: 0.1em 0; }
        li::marker { color: \(Theme.accentHex); }
        li.task { list-style: none; margin-left: -1.3em; }
        li.task input { accent-color: \(Theme.accentHex); margin: 0 0.35em 0 0; vertical-align: -1px; }
        .done { color: #85858B; text-decoration: line-through; }
        strong { color: #F5F5F7; }
        a { color: #8AB4F8; text-decoration: none; } a:hover { text-decoration: underline; }
        code { font: 0.92em ui-monospace, "SF Mono", Menlo, monospace; background: rgba(255,255,255,0.08); color: #E3C9A3; padding: 0 4px; border-radius: 3px; }
        pre { background: rgba(255,255,255,0.05); padding: 8px 10px; border-radius: 6px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { margin: 0.4em 0; padding: 0 0 0 10px; border-left: 2px solid #3A3A3E; color: #8E8E93; }
        hr { border: 0; border-top: 1px solid rgba(255,255,255,0.1); margin: 0.8em 0; }
        ::selection { background: rgba(226,166,88,0.35); }
        </style></head><body>
        \(body)
        </body></html>
        """
    }
}
