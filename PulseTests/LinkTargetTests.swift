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

    @Test func shiftClickPeeks() {
        #expect(LinkTarget(isLinkClick: true, buttonMask: 1, modifierFlags: .shift) == .peek)
        #expect(LinkTarget(isLinkClick: true, buttonMask: 1, modifierFlags: [.shift, .option]) == .asRequested)
        #expect(LinkTarget(isLinkClick: false, buttonMask: 0, modifierFlags: .shift) == .asRequested)
    }

    @Test func subdomainsAreTheSameSite() {
        let site = { (host: String) in URL(string: "https://\(host)")! }
        #expect(site("www.github.com/a").isSameSite(as: site("github.com/b")))
        #expect(site("gist.github.com").isSameSite(as: site("github.com")))
        #expect(!site("calendar.google.com").isSameSite(as: site("mail.google.com")))
        #expect(!site("notgithub.com").isSameSite(as: site("github.com")))
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
