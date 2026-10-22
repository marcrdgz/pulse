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

struct BrowserReorderTests {
    private func makeBrowser() -> Browser {
        let browser = Browser()
        for page in ["a", "b", "c"] {
            browser.openTab(url: URL(string: "https://\(page).com")!)
        }
        return browser
    }

    private func hosts(_ tabs: [Tab]) -> [String] {
        tabs.map { $0.url.host()!.replacingOccurrences(of: ".com", with: "") }
    }

    @Test func reordersWithinSection() {
        let browser = makeBrowser()
        browser.moveTab(browser.todayTabs[0], to: TabPosition(section: .today, index: 2))
        #expect(hosts(browser.todayTabs) == ["b", "a", "c"])
    }

    @Test func movingIntoPinnedPinsAtIndexAndKeepsSelection() {
        let browser = makeBrowser()
        browser.togglePin(browser.todayTabs[2])
        let tab = browser.todayTabs[0]

        browser.moveTab(tab, to: TabPosition(section: .pinned, index: 0))
        #expect(hosts(browser.pinnedTabs) == ["c", "a"])
        #expect(tab.pinnedURL == URL(string: "https://c.com")!)
        #expect(browser.activeTab === tab)
    }

    @Test func movingOutOfPinnedUnpins() {
        let browser = makeBrowser()
        let tab = browser.todayTabs[1]
        browser.togglePin(tab)

        browser.moveTab(tab, to: TabPosition(section: .today, index: 1))
        #expect(browser.pinnedTabs.isEmpty)
        #expect(hosts(browser.todayTabs) == ["c", "b", "a"])
        #expect(!tab.isPinned)
    }

    @Test func reorderingPinnedTabsKeepsTheirPinnedURL() {
        let browser = makeBrowser()
        let tab = browser.todayTabs[0]
        browser.togglePin(tab)
        browser.togglePin(browser.todayTabs[0])
        tab.load(URL(string: "https://elsewhere.com")!)

        browser.moveTab(tab, to: TabPosition(section: .pinned, index: 1))
        #expect(browser.position(of: tab) == TabPosition(section: .pinned, index: 1))
        #expect(tab.pinnedURL == URL(string: "https://c.com")!)
    }

    @Test func renamingOverridesTitleAndEmptyRestoresIt() {
        let browser = makeBrowser()
        let tab = browser.todayTabs[0]

        browser.rename(tab, to: "  Docs  ")
        #expect(tab.displayTitle == "Docs")
        browser.rename(tab, to: "")
        #expect(tab.displayTitle == "c.com")
    }
}
