import AppKit
import Testing
@testable import Pulse

struct LinkTargetTests {
    @Test func modifiedAndMiddleClicksOpenNewTabs() {
        #expect(LinkTarget(isLinkClick: true, buttonMask: 1, modifierFlags: []) == .asRequested)
        #expect(LinkTarget(isLinkClick: true, buttonMask: 1, modifierFlags: .command) == .newTab(activate: false))
        #expect(LinkTarget(isLinkClick: true, buttonMask: 1, modifierFlags: [.command, .shift]) == .newTab(activate: true))
        #expect(LinkTarget(isLinkClick: true, buttonMask: 4, modifierFlags: []) == .newTab(activate: false))
        #expect(LinkTarget(isLinkClick: true, buttonMask: 4, modifierFlags: .shift) == .newTab(activate: true))
    }

    @Test func navigationsThatArentClicksStayAsRequested() {
        #expect(LinkTarget(isLinkClick: false, buttonMask: 0, modifierFlags: .command) == .asRequested)
    }

    @Test func onlyNonWebSchemesOpenInOtherApps() {
        let external = ["mailto:a@b.com", "tel:+34600000000", "zoommtg://zoom.us/join", "itms-apps://x"]
        let web = ["https://a.com", "http://a.com", "about:blank", "data:text/plain,hi", "blob:https://a.com/1"]
        #expect(external.allSatisfy { URL(string: $0)!.opensInOtherApp })
        #expect(!web.contains { URL(string: $0)!.opensInOtherApp })
    }
}
