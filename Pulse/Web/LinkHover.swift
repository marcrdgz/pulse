import WebKit

/// Reports the link under the pointer so the window can preview its URL, like Chrome's status bubble.
/// WebKit has no public hover callback, so a script in an isolated world watches `mouseover`.
enum LinkHover {
    private static let messageName = "linkHover"

    static func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .defaultClient
        ))
        controller.add(Router.shared, contentWorld: .defaultClient, name: messageName)
    }

    private static let script = """
    (() => {
        let current = null;
        const post = (href) => {
            if (href === current) return;
            current = href;
            window.webkit.messageHandlers.\(messageName).postMessage(href);
        };
        document.addEventListener('mouseover', (event) => {
            const link = event.target instanceof Element ? event.target.closest('a[href], area[href]') : null;
            post(link && typeof link.href === 'string' ? link.href : null);
        }, true);
        // A null related target means the pointer left the page (or this frame).
        document.addEventListener('mouseout', (event) => { if (!event.relatedTarget) post(null); }, true);
        window.addEventListener('pagehide', () => post(null));
    })();
    """

    /// One handler for every web view: popups share their opener's content controller,
    /// so the message is routed by the web view that sent it rather than by who registered it.
    private final class Router: NSObject, WKScriptMessageHandler {
        static let shared = Router()

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            let coordinator = message.webView?.navigationDelegate as? WebViewCoordinator
            coordinator?.hoveredLinkDidChange(to: message.body as? String)
        }
    }
}
