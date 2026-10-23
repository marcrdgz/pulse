import AppKit
import Foundation
import Testing
@testable import Pulse

struct ContextMenuTests {
    private let a = URL(string: "https://a.com/")!
    private let b = URL(string: "https://b.com/")!
    private let c = URL(string: "https://c.com/")!

    /// Stands in for WebKit's menu target, which reads what was clicked from the item it's sent.
    private final class WebKitTarget: NSObject {
        var sender: NSMenuItem?

        @objc func forwardContextMenuAction(_ sender: NSMenuItem) {
            self.sender = sender
        }
    }

    private func webKitMenu(_ items: [(String, String)], target: WebKitTarget) -> NSMenu {
        let menu = NSMenu()
        for (identifier, title) in items {
            let item = NSMenuItem(title: title, action: #selector(WebKitTarget.forwardContextMenuAction), keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(identifier)
            item.target = target
            menu.addItem(item)
        }
        return menu
    }

    private func coordinator(of tab: Tab) -> WebViewCoordinator {
        tab.webView.uiDelegate as! WebViewCoordinator
    }

    private func perform(_ item: NSMenuItem) {
        NSApp.sendAction(item.action!, to: item.target, from: item)
    }

    @Test func linkMenuOpensTabsInsteadOfWindows() {
        let browser = Browser()
        let work = browser.createSpace()
        browser.selectSpace(browser.spaces[0])
        let page = browser.openTab(url: a)
        let target = WebKitTarget()
        let menu = webKitMenu([
            ("WKMenuItemIdentifierOpenLink", "Open Link"),
            ("WKMenuItemIdentifierOpenLinkInNewWindow", "Open Link in New Window"),
            ("WKMenuItemIdentifierCopyLink", "Copy Link"),
        ], target: target)

        coordinator(of: page).customize(menu, in: page.webView)
        #expect(menu.items.map(\.title) == ["Open Link", "Open Link in New Tab", "Open Link in Space", "Copy Link"])
        #expect(menu.items[2].submenu?.items.map(\.title) == [work.name])

        perform(menu.items[1])
        #expect(target.sender?.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow")
        #expect(coordinator(of: page).openForContextMenu(b))
        #expect(browser.todayTabs.map(\.url) == [b, a])
        #expect(browser.activeTab === page)
        #expect(browser.todayTabs[0].opener === page)
        // Windows the page opens itself afterwards aren't redirected.
        #expect(!coordinator(of: page).openForContextMenu(c))
    }

    @Test func openingLinkInSpaceFollowsIt() {
        let browser = Browser()
        let work = browser.createSpace()
        browser.selectSpace(browser.spaces[0])
        let page = browser.openTab(url: a)
        let menu = webKitMenu([("WKMenuItemIdentifierOpenLinkInNewWindow", "Open Link in New Window")], target: WebKitTarget())

        coordinator(of: page).customize(menu, in: page.webView)
        perform(menu.items[1].submenu!.items[0])
        #expect(coordinator(of: page).openForContextMenu(b))
        #expect(browser.activeSpace === work)
        #expect(browser.activeTab?.url == b)
    }

    @Test func imageAndSelectionMenusUsePulse() {
        let browser = Browser()
        let page = browser.openTab(url: a)
        let menu = webKitMenu([
            ("WKMenuItemIdentifierOpenImageInNewWindow", "Open Image in New Window"),
            ("WKMenuItemIdentifierDownloadImage", "Download Image"),
            ("WKMenuItemIdentifierCopyImage", "Copy Image"),
            ("WKMenuItemIdentifierSearchWeb", "Search with Google"),
        ], target: WebKitTarget())

        coordinator(of: page).customize(menu, in: page.webView)
        #expect(menu.items.map(\.title) == [
            "Open Image in New Tab", "Download Image", "Copy Image", "Copy Image Address",
            "Search with \(browser.preferences.searchEngine.name)",
        ])
    }

    @Test func pageMenuAddsCopyShareAndPrint() {
        let browser = Browser()
        let page = browser.openTab(url: a)
        let menu = webKitMenu([
            ("WKMenuItemIdentifierGoBack", "Back"),
            ("WKMenuItemIdentifierReload", "Reload Page"),
        ], target: WebKitTarget())

        coordinator(of: page).customize(menu, in: page.webView)
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        #expect(titles.first == "Back")
        #expect(titles.contains("Copy URL"))
        #expect(titles.last == "Print…")
    }

    @Test func duplicateOpensBelowTheOriginal() {
        let browser = Browser()
        browser.openTab(url: a)
        let original = browser.openTab(url: b)
        browser.openTab(url: c)

        browser.duplicate(original)
        #expect(browser.todayTabs.map(\.url) == [c, b, b, a])
        #expect(browser.activeTab === browser.todayTabs[2])
    }

    @Test func closingTabsBelowAndOthersCanBeReopened() {
        let browser = Browser()
        browser.openTab(url: a)
        browser.openTab(url: b)
        let top = browser.openTab(url: c)

        browser.closeTabs(below: browser.todayTabs[1])
        #expect(browser.todayTabs.map(\.url) == [c, b])

        browser.closeOtherTabs(than: top)
        #expect(browser.todayTabs.map(\.url) == [c])
        browser.reopenClosedTab()
        #expect(browser.todayTabs.map(\.url).contains(b))
    }

    @Test func pinnedTabCanKeepItsCurrentPage() {
        let browser = Browser()
        let tab = browser.openTab(url: a)
        browser.togglePin(tab)
        tab.load(b)

        browser.updatePinnedURL(of: tab)
        browser.close(tab)
        #expect(tab.url == b)
    }
}
