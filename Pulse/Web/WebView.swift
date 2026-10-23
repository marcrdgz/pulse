import SwiftUI
import WebKit

/// Shows the active tab's own web view, so switching tabs never reloads a page.
struct WebView: NSViewRepresentable {
    let tab: Tab
    /// Both panes of a split view are on screen; only the active tab's takes keyboard focus.
    var takesFocus = true

    final class Coordinator {
        var hadFocus = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

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
        let isNewlyShown = webView.superview !== container
        if isNewlyShown {
            container.subviews.forEach { $0.removeFromSuperview() }
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }
        // Only on a change, so focus isn't pulled back from the command bar or find bar on every update.
        if takesFocus, isNewlyShown || !context.coordinator.hadFocus {
            container.window?.makeFirstResponder(webView)
        }
        context.coordinator.hadFocus = takesFocus
    }
}
