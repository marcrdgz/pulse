import Foundation
import Testing
@testable import Pulse

struct BrowserTests {
    /// Opens the pages in order; since new tabs go on top, `todayTabs` ends up reversed.
    private func makeBrowser(_ pages: String...) -> Browser {
        let browser = Browser()
        for page in pages {
            browser.openTab(url: URL(string: "https://\(page).com")!)
        }
        return browser
    }

    private func hosts(_ tabs: [Tab]) -> [String] {
        tabs.map { $0.url.host()!.replacingOccurrences(of: ".com", with: "") }
    }

    @Test func startsWithCommandBarWhenThereAreNoTabs() {
        #expect(Browser().commandBar == .newTab)
    }

    @Test func newTabsGoOnTopAndBecomeActive() {
        let browser = makeBrowser("a", "b", "c")
        #expect(hosts(browser.todayTabs) == ["c", "b", "a"])
        #expect(browser.activeTab === browser.todayTabs[0])
    }

    @Test func backgroundTabsKeepSelection() {
        let browser = makeBrowser("a")
        browser.openTab(url: URL(string: "https://b.com")!, activate: false)
        #expect(hosts(browser.activeTab.map { [$0] } ?? []) == ["a"])
    }

    @Test func closingActiveTabSelectsTabBelowThenAbove() {
        let browser = makeBrowser("a", "b", "c")
        browser.select(browser.todayTabs[1])

        browser.closeActiveTab()
        #expect(hosts(browser.todayTabs) == ["c", "a"])
        #expect(hosts([browser.activeTab!]) == ["a"])

        browser.closeActiveTab()
        #expect(hosts([browser.activeTab!]) == ["c"])
    }

    @Test func closingLastTabOpensCommandBar() {
        let browser = makeBrowser("a")
        browser.dismissCommandBar()
        browser.closeActiveTab()
        #expect(browser.activeTab == nil)
        #expect(browser.commandBar == .newTab)
    }

    @Test func reopenRestoresPositionAndSelects() {
        let browser = makeBrowser("a", "b", "c")
        browser.close(browser.todayTabs[1])
        #expect(browser.canReopenClosedTab)

        browser.reopenClosedTab()
        #expect(hosts(browser.todayTabs) == ["c", "b", "a"])
        #expect(hosts([browser.activeTab!]) == ["b"])
        #expect(!browser.canReopenClosedTab)
    }

    @Test func closingPinnedTabResetsItInsteadOfRemovingIt() {
        let browser = makeBrowser("a", "b")
        let pinned = browser.todayTabs[0]
        browser.togglePin(pinned)
        #expect(hosts(browser.pinnedTabs) == ["b"])
        #expect(hosts(browser.todayTabs) == ["a"])

        pinned.load(URL(string: "https://elsewhere.com")!)
        browser.close(pinned)
        #expect(browser.pinnedTabs.map(\.id) == [pinned.id])
        #expect(hosts([pinned]) == ["b"])
        #expect(hosts([browser.activeTab!]) == ["a"])
    }

    @Test func unpinningMovesTabToTopOfToday() {
        let browser = makeBrowser("a", "b")
        let tab = browser.todayTabs[1]
        browser.togglePin(tab)
        browser.togglePin(tab)
        #expect(browser.pinnedTabs.isEmpty)
        #expect(hosts(browser.todayTabs) == ["a", "b"])
        #expect(!tab.isPinned)
    }

    @Test func numberShortcutsCountPinnedTabsFirstAndNineSelectsLast() {
        let browser = makeBrowser("a", "b", "c")
        browser.togglePin(browser.todayTabs[2])

        browser.selectTab(number: 1)
        #expect(hosts([browser.activeTab!]) == ["a"])
        browser.selectTab(number: 2)
        #expect(hosts([browser.activeTab!]) == ["c"])
        browser.selectTab(number: 9)
        #expect(hosts([browser.activeTab!]) == ["b"])

        browser.selectTab(number: 5)
        #expect(hosts([browser.activeTab!]) == ["b"])
    }

    @Test func adjacentTabSelectionWraps() {
        let browser = makeBrowser("a", "b", "c")
        browser.selectAdjacentTab(offset: -1)
        #expect(hosts([browser.activeTab!]) == ["a"])
        browser.selectAdjacentTab(offset: 1)
        #expect(hosts([browser.activeTab!]) == ["c"])
    }

    @Test func commandBarEditsActiveTabOrOpensNewOne() {
        let browser = makeBrowser("a")
        let url = URL(string: "https://b.com")!

        browser.showCommandBar(.editActiveTab)
        browser.open(url, from: .editActiveTab)
        #expect(hosts(browser.todayTabs) == ["b"])
        #expect(browser.commandBar == nil)

        browser.open(URL(string: "https://c.com")!, from: .newTab)
        #expect(hosts(browser.todayTabs) == ["c", "b"])
    }
}

struct BrowserFindTests {
    @Test func findBarClosesWhenSwitchingTabs() {
        let browser = Browser()
        let first = browser.openTab(url: URL(string: "https://a.com")!)
        browser.openTab(url: URL(string: "https://b.com")!)

        browser.showFindBar()
        #expect(browser.isFindBarVisible)
        browser.select(first)
        #expect(!browser.isFindBarVisible)
    }
}
