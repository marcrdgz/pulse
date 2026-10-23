import AppKit
import WebKit

/// Lets the tab's coordinator rewrite WebKit's context menu before it opens.
final class BrowserWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        (uiDelegate as? WebViewCoordinator)?.customize(menu, in: self)
    }
}

/// Where a rewritten "Open … in New Window" item sends the window WebKit then asks for.
enum ContextMenuOpen: Equatable {
    case backgroundTab
    case space(Space.ID)
    case copyAddress
}

/// WebKit's own identifiers (`_WKMenuItemIdentifier…` SPI, whose values are their names).
/// Its items know what was clicked, which WebKit doesn't expose, so Pulse keeps them and only
/// redirects what they open.
enum WebKitMenuItem {
    static let openLinkInNewWindow = "WKMenuItemIdentifierOpenLinkInNewWindow"
    static let openImageInNewWindow = "WKMenuItemIdentifierOpenImageInNewWindow"
    static let openMediaInNewWindow = "WKMenuItemIdentifierOpenMediaInNewWindow"
    static let openFrameInNewWindow = "WKMenuItemIdentifierOpenFrameInNewWindow"
    static let copyImage = "WKMenuItemIdentifierCopyImage"
    static let searchWeb = "WKMenuItemIdentifierSearchWeb"
    static let reload = "WKMenuItemIdentifierReload"
}

extension WebViewCoordinator {
    /// Like Chrome's menu: links, images and media open in background tabs (or another space)
    /// instead of windows, searches use Pulse's engine, and the page menu can copy, share and print.
    func customize(_ menu: NSMenu, in webView: WKWebView) {
        pendingContextMenuOpen = nil
        guard let tab, let browser = tab.browser else { return }
        let original = menu.items
        let openImage = original.first { $0.identifier?.rawValue == WebKitMenuItem.openImageInNewWindow }
        menu.removeAllItems()
        for item in original {
            switch item.identifier?.rawValue {
            case WebKitMenuItem.openLinkInNewWindow:
                menu.addItem(redirect(item, title: "Open Link in New Tab", to: .backgroundTab))
                let otherSpaces = browser.spaces.filter { $0.id != browser.activeSpaceID }
                if !otherSpaces.isEmpty {
                    let spaces = NSMenuItem(title: "Open Link in Space", action: nil, keyEquivalent: "")
                    spaces.submenu = NSMenu()
                    for space in otherSpaces {
                        spaces.submenu?.addItem(redirect(item, title: space.name, to: .space(space.id)))
                    }
                    menu.addItem(spaces)
                }
            case WebKitMenuItem.openImageInNewWindow, WebKitMenuItem.openMediaInNewWindow,
                 WebKitMenuItem.openFrameInNewWindow:
                let title = item.title.replacingOccurrences(of: "New Window", with: "New Tab")
                menu.addItem(redirect(item, title: title, to: .backgroundTab))
            case WebKitMenuItem.copyImage:
                menu.addItem(item)
                if let openImage {
                    menu.addItem(redirect(openImage, title: "Copy Image Address", to: .copyAddress))
                }
            case WebKitMenuItem.searchWeb:
                // WebKit's item hands the text to the system's Services, which may open another browser.
                let engine = browser.preferences.searchEngine
                menu.addItem(NSMenuItem("Search with \(engine.name)") { [weak self, weak webView] in
                    if let webView { self?.searchSelection(in: webView) }
                })
            case WebKitMenuItem.reload:
                menu.addItem(item)
                menu.addItem(.separator())
                menu.addItem(NSMenuItem("Copy URL") { [weak browser, weak tab] in
                    if let tab { browser?.copyURL(of: tab) }
                })
                menu.addItem(NSSharingServicePicker(items: [tab.url]).standardShareMenuItem)
                menu.addItem(NSMenuItem("Print…") { [weak webView] in webView?.printPage() })
            default:
                menu.addItem(item)
            }
        }
    }

    /// Consumes the redirect a context menu item set up; `false` when the window wasn't asked for by one.
    func openForContextMenu(_ url: URL) -> Bool {
        guard let open = pendingContextMenuOpen, let tab, let browser = tab.browser else { return false }
        pendingContextMenuOpen = nil
        switch open {
        case .backgroundTab:
            browser.openTab(url: url, activate: false).opener = tab
        case .space(let id):
            guard let space = browser.spaces.first(where: { $0.id == id }) else { return true }
            browser.openTab(url: url, in: space)
        case .copyAddress:
            browser.copyLink(url)
        }
        return true
    }

    /// Runs WebKit's item, which asks for a new window with whatever was clicked, after noting
    /// where that window should go instead.
    private func redirect(_ item: NSMenuItem, title: String, to open: ContextMenuOpen) -> NSMenuItem {
        NSMenuItem(title) { [weak self] in
            guard let action = item.action else { return }
            self?.pendingContextMenuOpen = open
            NSApp.sendAction(action, to: item.target, from: item)
        }
    }

    /// Opens a foreground tab next to the page, like Chrome's "Search Google for".
    private func searchSelection(in webView: WKWebView) {
        webView.evaluateJavaScript("window.getSelection().toString()") { [weak self] result, _ in
            guard let tab = self?.tab, let browser = tab.browser,
                  let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  let url = browser.preferences.searchEngine.searchURL(for: text)
            else { return }
            browser.openTab(url: url).opener = tab
        }
    }
}

private extension WKWebView {
    func printPage() {
        guard let window else { return }
        let operation = printOperation(with: .shared)
        // Without a frame WebKit prints blank pages.
        operation.view?.frame = bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}

extension NSMenuItem {
    /// An item that runs a closure, for menus built outside SwiftUI.
    convenience init(_ title: String, handler: @escaping () -> Void) {
        let action = MenuAction(handler)
        self.init(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        target = action
        // `target` is weak; the item keeps its action alive.
        representedObject = action
    }
}

private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}
