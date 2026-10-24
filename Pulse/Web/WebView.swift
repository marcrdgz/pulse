import SwiftUI
import WebKit

/// Shows the active tab's own web view, so switching tabs never reloads a page.
struct WebView: NSViewRepresentable {
    let tab: Tab
    /// Both panes of a split view are on screen; only the active tab's takes keyboard focus.
    var takesFocus = true

    final class Coordinator {
        var hadFocus = false
        /// The web view this container last showed, to tell a page another container took from one never shown.
        weak var shownWebView: WKWebView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Lets go of the page, so a container that gave it up can tell it's free to show again.
    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }

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
        // A container still on screen while it animates out, like Peek's card after "Open as Tab",
        // must not take the page back from the pane that took it, or the pane goes blank. The pane
        // may not be in the window yet, so a page with any superview counts as taken.
        if isNewlyShown, webView === context.coordinator.shownWebView, webView.superview != nil { return }
        if isNewlyShown {
            context.coordinator.shownWebView = webView
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
