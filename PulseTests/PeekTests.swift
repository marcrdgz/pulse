import Foundation
import Testing
@testable import Pulse

struct PeekTests {
    private let gmail = URL(string: "https://mail.google.com")!
    private let article = URL(string: "https://example.com/article")!

    private func makeBrowser() -> (Browser, pinned: Tab) {
        let browser = Browser()
        let pinned = browser.openTab(url: gmail)
        browser.togglePin(pinned)
        return (browser, pinned)
    }

    @Test func pinnedTabsPeekAtLinksToOtherSitesOnly() {
        let (browser, pinned) = makeBrowser()
        #expect(browser.opensInPeek(article, clickedIn: pinned, target: .asRequested, leavesPage: true))
        #expect(!browser.opensInPeek(gmail.appending(path: "inbox"), clickedIn: pinned, target: .asRequested, leavesPage: true))
        #expect(!browser.opensInPeek(article, clickedIn: pinned, target: .asRequested, leavesPage: false))
        #expect(!browser.opensInPeek(article, clickedIn: pinned, target: .newTab(activate: false), leavesPage: true))

        browser.preferences.opensPinnedLinksInPeek = false
        #expect(!browser.opensInPeek(article, clickedIn: pinned, target: .asRequested, leavesPage: true))
        #expect(browser.opensInPeek(article, clickedIn: pinned, target: .peek, leavesPage: true))

        let today = browser.openTab(url: gmail)
        #expect(!browser.opensInPeek(article, clickedIn: today, target: .asRequested, leavesPage: true))
    }

    @Test func peekIsNotATabUntilExpanded() {
        let (browser, pinned) = makeBrowser()
        browser.openPeek(article, from: pinned)
        #expect(browser.focusedTab === browser.peek)
        #expect(!browser.allTabs.contains { $0.url == article })
        #expect(browser.canExpandPeekIntoSplitView)

        browser.expandPeek()
        #expect(browser.peek == nil)
        #expect(browser.activeTab?.url == article)
        #expect(browser.todayTabs.first === browser.activeTab)

        browser.closeActiveTab()
        #expect(browser.activeTab === pinned, "closing the expanded page returns to the pinned tab")
    }

    @Test func expandingIntoSplitViewKeepsThePinnedTabBeside() {
        let (browser, pinned) = makeBrowser()
        browser.openPeek(article, from: pinned)
        browser.expandPeek(intoSplitView: true)
        #expect(browser.visibleTabs.map(\.url) == [gmail, article])
    }

    @Test func closeTabAndSwitchingTabsClosePeek() {
        let (browser, pinned) = makeBrowser()
        let other = browser.openTab(url: article, activate: false)
        browser.openPeek(article, from: pinned)

        browser.closeActiveTab()
        #expect(browser.peek == nil)
        #expect(browser.activeTab === pinned, "⌘W closes Peek, not the page under it")

        browser.openPeek(article, from: pinned)
        browser.select(other)
        #expect(browser.peek == nil)
    }

    @Test func favoritesCantExpandPeekIntoSplitView() {
        let (browser, pinned) = makeBrowser()
        browser.toggleFavorite(pinned)
        browser.openPeek(article, from: pinned)
        #expect(!browser.canExpandPeekIntoSplitView)
        browser.expandPeek(intoSplitView: true)
        #expect(browser.activeSplit == nil)
        #expect(browser.activeTab?.url == article)
    }
}
