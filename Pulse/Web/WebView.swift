import SwiftUI
import WebKit

/// Shows the active tab's own web view, so switching tabs never reloads a page.
struct WebView: NSViewRepresentable {
    let tab: Tab

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = Theme.contentCornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let webView = tab.webView
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        container.window?.makeFirstResponder(webView)
    }
}
