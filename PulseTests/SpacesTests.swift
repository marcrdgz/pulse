import Foundation
import Testing
@testable import Pulse

struct SpacesTests {
    private let a = URL(string: "https://a.com")!
    private let b = URL(string: "https://b.com")!
    private let c = URL(string: "https://c.com")!

    @Test func newSpaceStartsEmptyWithCommandBarAndNextTheme() {
        let browser = Browser()
        browser.openTab(url: a)
        browser.dismissCommandBar()

        let space = browser.createSpace()
        #expect(browser.activeSpace === space)
        #expect(browser.todayTabs.isEmpty)
        #expect(browser.activeTab == nil)
        #expect(browser.commandBar == .newTab)
        #expect(space.theme != browser.spaces[0].theme)
    }

    @Test func eachSpaceRemembersItsActiveTab() {
        let browser = Browser()
        let home = browser.activeSpace
        let homeTab = browser.openTab(url: a)
        let work = browser.createSpace()
        let workTab = browser.openTab(url: b)

        browser.selectSpace(home)
        #expect(browser.activeTab === homeTab)
        browser.selectSpace(work)
        #expect(browser.activeTab === workTab)
    }

    @Test func favoritesAreSharedAcrossSpaces() {
        let browser = Browser()
        let favorite = browser.openTab(url: a)
        browser.toggleFavorite(favorite)
        browser.createSpace()

        #expect(browser.allTabs.first === favorite)
        browser.select(favorite)
        #expect(browser.activeSpace === browser.spaces[1])
        #expect(browser.activeTab === favorite)
    }

    @Test func selectingTabFromAnotherSpaceSwitchesToIt() {
        let browser = Browser()
        let home = browser.activeSpace
        let homeTab = browser.openTab(url: a)
        browser.createSpace()

        browser.switchTo(homeTab)
        #expect(browser.activeSpace === home)
        #expect(browser.everyTab.first === homeTab)
    }

    @Test func movingTabToAnotherSpaceFollowsIt() {
        let browser = Browser()
        let home = browser.activeSpace
        let work = browser.createSpace()
        browser.selectSpace(home)
        let tab = browser.openTab(url: a)
        browser.togglePin(tab)

        browser.moveTab(tab, to: work)
        #expect(home.tabs.isEmpty)
        #expect(work.todayTabs.first === tab)
        #expect(!tab.isPinned)
        #expect(browser.activeSpace === work)
        #expect(browser.activeTab === tab)
    }

    @Test func reopenedTabReturnsToItsSpace() {
        let browser = Browser()
        let home = browser.activeSpace
        browser.openTab(url: a)
        browser.closeActiveTab()
        browser.createSpace()

        browser.reopenClosedTab()
        #expect(browser.activeSpace === home)
        #expect(browser.activeTab?.url == a)
    }

    @Test func deletingSpaceClosesItsTabsButKeepsFavorites() {
        let browser = Browser()
        let home = browser.activeSpace
        let favorite = browser.openTab(url: a)
        browser.toggleFavorite(favorite)
        let work = browser.createSpace()
        browser.openTab(url: b)

        browser.delete(work)
        #expect(browser.spaces.map(\.id) == [home.id])
        #expect(browser.activeSpace === home)
        #expect(browser.favorites.first === favorite)

        browser.delete(home)
        #expect(browser.spaces.count == 1)
    }

    @Test func spaceShortcutsDontWrap() {
        let browser = Browser()
        browser.createSpace()
        browser.createSpace()

        browser.selectSpace(number: 1)
        browser.selectAdjacentSpace(offset: -1)
        #expect(browser.activeSpaceIndex == 0)
        browser.selectSpace(number: 3)
        browser.selectAdjacentSpace(offset: 1)
        #expect(browser.activeSpaceIndex == 2)
        browser.selectSpace(number: 7)
        #expect(browser.activeSpaceIndex == 2)
    }

    @Test func draggingIntoFavoritesAndBack() {
        let browser = Browser()
        let tab = browser.openTab(url: a)
        browser.openTab(url: b)

        browser.moveTab(tab, to: TabPosition(section: .favorites, index: 0))
        #expect(browser.position(of: tab) == TabPosition(section: .favorites, index: 0))
        #expect(tab.pinnedURL == a)

        browser.moveTab(tab, to: TabPosition(section: .pinned, index: 0))
        #expect(browser.favorites.isEmpty)
        #expect(browser.pinnedTabs.first === tab)
        #expect(tab.pinnedURL == a)
    }

    @Test func renamingSpaceIgnoresBlankNames() {
        let browser = Browser()
        browser.rename(browser.activeSpace, to: "  Personal ")
        browser.rename(browser.activeSpace, to: "   ")
        #expect(browser.activeSpace.name == "Personal")
    }
}
