import Foundation
import Testing
@testable import Pulse

struct SplitViewTests {
    /// Opens the pages in order; since new tabs go on top, `todayTabs` ends up reversed.
    private func makeBrowser(_ pages: String..., sessionStore: SessionStore? = nil) -> Browser {
        let browser = Browser(sessionStore: sessionStore)
        for page in pages {
            browser.openTab(url: URL(string: "https://\(page).com")!)
        }
        return browser
    }

    private func hosts(_ tabs: [Tab]) -> [String] {
        tabs.map { $0.url.host()!.replacingOccurrences(of: ".com", with: "") }
    }

    @Test func splittingShowsBothTabsAndFocusesTheNewOne() {
        let browser = makeBrowser("a", "b", "c")
        let (c, a) = (browser.todayTabs[0], browser.todayTabs[2])

        browser.splitView(c, with: a)
        #expect(hosts(browser.visibleTabs) == ["c", "a"])
        #expect(browser.activeTab === a)

        browser.select(browser.todayTabs[1])
        #expect(hosts(browser.visibleTabs) == ["b"])
        browser.select(c)
        #expect(hosts(browser.visibleTabs) == ["c", "a"])
    }

    @Test func closingAPaneLeavesItsPartnerOnScreen() {
        let browser = makeBrowser("a", "b", "c")
        browser.splitView(browser.todayTabs[0], with: browser.todayTabs[2])

        browser.closeActiveTab()
        #expect(hosts(browser.visibleTabs) == ["c"])
        #expect(browser.activeSplit == nil)
    }

    @Test func leavingTheSpaceSeparatesTheSplit() {
        let browser = makeBrowser("a", "b")
        let (b, a) = (browser.todayTabs[0], browser.todayTabs[1])
        browser.splitView(b, with: a)
        browser.toggleFavorite(a)
        #expect(browser.activeSpace.splits.isEmpty)

        browser.toggleFavorite(a)
        browser.splitView(b, with: a)
        browser.togglePin(a)
        #expect(browser.activeSplit != nil, "pinning keeps the tab in its space")

        browser.moveTab(a, to: browser.createSpace())
        #expect(browser.spaces.allSatisfy { $0.splits.isEmpty })
    }

    @Test func favoritesCantSplit() {
        let browser = makeBrowser("a", "b")
        browser.toggleFavorite(browser.todayTabs[0])
        #expect(!browser.canSplit(browser.favorites[0], with: browser.todayTabs[0]))
        #expect(!browser.canSplit(browser.todayTabs[0], with: browser.favorites[0]))
    }

    @Test func splittingATabTakesItOutOfItsPreviousSplit() {
        let browser = makeBrowser("a", "b", "c")
        let (c, b, a) = (browser.todayTabs[0], browser.todayTabs[1], browser.todayTabs[2])
        browser.splitView(a, with: b)
        browser.splitView(c, with: b)
        #expect(browser.activeSpace.splits == [TabSplit(leading: c.id, trailing: b.id)])
    }

    @Test func droppingATabOnThePageSplitsOnThatSide() throws {
        let browser = makeBrowser("a", "b")
        let (b, a) = (browser.todayTabs[0], browser.todayTabs[1])
        #expect(browser.tabKept(droppingTab: b, on: .leading) == nil, "the page shown can't split with itself")

        let kept = try #require(browser.tabKept(droppingTab: a, on: .leading))
        browser.splitView(kept, with: a, on: .leading)
        #expect(hosts(browser.visibleTabs) == ["a", "b"])
        #expect(browser.activeTab === a)
    }

    @Test func droppingOnASplitReplacesThatPaneAndKeepsTheWidths() {
        let browser = makeBrowser("a", "b", "c")
        let (c, b, a) = (browser.todayTabs[0], browser.todayTabs[1], browser.todayTabs[2])
        browser.splitView(a, with: b)
        browser.setSplitRatio(0.3)

        #expect(browser.tabKept(droppingTab: c, on: .trailing) === a)
        browser.splitView(a, with: c, on: .trailing)
        #expect(hosts(browser.visibleTabs) == ["a", "c"])
        #expect(browser.activeSplit?.ratio == 0.3)
        #expect(browser.tabKept(droppingTab: a, on: .trailing) == nil)
    }

    @Test func commandBarOpensThePageNextToTheActiveTab() {
        let browser = makeBrowser("a")
        browser.showCommandBar(.splitView)
        browser.open(URL(string: "https://b.com")!, from: .splitView)
        #expect(hosts(browser.visibleTabs) == ["a", "b"])
        #expect(hosts([browser.activeTab!]) == ["b"])
    }

    @Test func ratioIsClamped() {
        let browser = makeBrowser("a", "b")
        browser.splitView(browser.todayTabs[0], with: browser.todayTabs[1])
        browser.setSplitRatio(0.05)
        #expect(browser.activeSplit?.ratio == TabSplit.ratioRange.lowerBound)
    }

    @Test func splitsAreRestoredWithTheSession() throws {
        let store = SessionStore(
            fileURL: FileManager.default.temporaryDirectory
                .appending(path: "PulseTests-\(UUID().uuidString)")
                .appending(path: "session.json")
        )
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let browser = makeBrowser("a", "b", sessionStore: store)
        browser.splitView(browser.todayTabs[0], with: browser.todayTabs[1])
        browser.setSplitRatio(0.3)
        browser.saveSession()

        let restored = Browser(sessionStore: store)
        #expect(restored.activeSplit == browser.activeSplit)
        #expect(hosts(restored.visibleTabs) == ["b", "a"])
    }

    @Test func splitsOfMissingTabsAreDropped() {
        let tab = Tab(url: URL(string: "https://a.com")!)
        let space = Space(name: "Work", theme: .blue, todayTabs: [tab], splits: [TabSplit(leading: tab.id, trailing: UUID())])
        #expect(space.splits.isEmpty)
    }
}
