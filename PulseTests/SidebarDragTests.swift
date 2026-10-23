import Foundation
import Testing
@testable import Pulse

struct SidebarDragTests {
    private let browser = Browser()
    private let drag = SidebarDragController()

    /// A sidebar with "Home" (active, one today tab) and "Work", laid out in window coordinates.
    private func layOut() -> (home: Space, work: Space, tab: Tab) {
        let home = browser.activeSpace
        let work = browser.createSpace()
        browser.rename(work, to: "Work")
        browser.selectSpace(home)
        let tab = browser.openTab(url: URL(string: "https://a.com")!)

        drag.tabFrames[tab.id] = CGRect(x: 0, y: 100, width: 200, height: 30)
        drag.todayAreaFrame = CGRect(x: 0, y: 100, width: 200, height: 400)
        drag.spaceSwitcherFrame = CGRect(x: 0, y: 600, width: 200, height: 28)
        drag.spaceDotFrames = [
            home.id: CGRect(x: 0, y: 603, width: 22, height: 22),
            work.id: CGRect(x: 24, y: 603, width: 22, height: 22),
        ]
        return (home, work, tab)
    }

    @Test func droppingOnASpaceDotMovesTheTabThere() {
        let (home, work, tab) = layOut()

        drag.drag(tab, to: CGPoint(x: 50, y: 110), in: browser)
        drag.drag(tab, to: CGPoint(x: 35, y: 614), in: browser)
        #expect(drag.hoveredSpaceID == work.id)
        drag.drop(tab, at: CGPoint(x: 35, y: 614), in: browser)

        #expect(home.tabs.isEmpty)
        #expect(work.todayTabs.first === tab)
        #expect(browser.activeSpace === work)
        #expect(drag.hoveredSpaceID == nil)
    }

    /// The current space's dot still shows its name, but dropping there changes nothing.
    @Test func droppingOnTheCurrentSpaceKeepsTheTab() {
        let (home, _, tab) = layOut()

        drag.drag(tab, to: CGPoint(x: 50, y: 110), in: browser)
        drag.drag(tab, to: CGPoint(x: 11, y: 614), in: browser)
        #expect(drag.hoveredSpaceID == home.id)
        drag.drop(tab, at: CGPoint(x: 11, y: 614), in: browser)

        #expect(home.todayTabs.map(\.id) == [tab.id])
        #expect(browser.activeSpace === home)
    }

    /// The switcher sits below the today tabs, but dropping on it between dots is no move to today.
    @Test func droppingOnTheSwitcherBetweenDotsKeepsTheTab() {
        let (home, _, tab) = layOut()
        let other = browser.openTab(url: URL(string: "https://b.com")!)
        drag.tabFrames[other.id] = CGRect(x: 0, y: 100, width: 200, height: 30)
        drag.tabFrames[tab.id] = CGRect(x: 0, y: 130, width: 200, height: 30)

        drag.drag(tab, to: CGPoint(x: 50, y: 140), in: browser)
        drag.drag(tab, to: CGPoint(x: 150, y: 614), in: browser)
        #expect(drag.hoveredSpaceID == nil)
        drag.drop(tab, at: CGPoint(x: 150, y: 614), in: browser)

        #expect(home.todayTabs.last === tab)
        #expect(browser.activeSpace === home)
    }

    @Test func leavingTheSwitcherClearsTheHoveredSpace() {
        let (_, work, tab) = layOut()

        drag.drag(tab, to: CGPoint(x: 35, y: 614), in: browser)
        #expect(drag.hoveredSpaceID == work.id)
        drag.drag(tab, to: CGPoint(x: 50, y: 300), in: browser)

        #expect(drag.hoveredSpaceID == nil)
    }
}
