import Foundation
import Testing
import WebKit
@testable import Pulse

struct SitePermissionsTests {
    private let defaults = UserDefaults(suiteName: "PulseTests-\(UUID().uuidString)")!

    private func makeBrowser() -> (Browser, Tab) {
        let browser = Browser(sitePermissions: SitePermissionStore(defaults: defaults))
        return (browser, browser.openTab(url: URL(string: "https://meet.google.com")!))
    }

    @Test func promptsThenRemembersAllowAlways() {
        let (browser, tab) = makeBrowser()
        var decisions: [WKPermissionDecision] = []

        browser.requestPermission(from: tab, origin: "meet.google.com", kinds: [.camera, .microphone]) { decisions.append($0) }
        let request = try! #require(browser.activePermissionRequest)
        browser.answer(request, with: .allowAlways)
        browser.requestPermission(from: tab, origin: "meet.google.com", kinds: [.camera]) { decisions.append($0) }

        #expect(decisions == [.grant, .grant])
        #expect(browser.permissionRequests.isEmpty)
    }

    @Test func allowOnceAsksAgainAndNeverAllowDeniesSilently() {
        let (browser, tab) = makeBrowser()
        var decisions: [WKPermissionDecision] = []

        browser.requestPermission(from: tab, origin: "a.com", kinds: [.microphone]) { decisions.append($0) }
        browser.answer(browser.activePermissionRequest!, with: .allowOnce)
        browser.requestPermission(from: tab, origin: "a.com", kinds: [.microphone]) { decisions.append($0) }
        #expect(browser.activePermissionRequest != nil)

        browser.answer(browser.activePermissionRequest!, with: .neverAllow)
        browser.requestPermission(from: tab, origin: "a.com", kinds: [.microphone]) { decisions.append($0) }
        #expect(decisions == [.grant, .deny, .deny])
    }

    @Test func partialDecisionsStillPrompt() {
        let (browser, tab) = makeBrowser()
        SitePermissionStore(defaults: defaults).save(true, for: "a.com", kinds: [.camera])

        browser.requestPermission(from: tab, origin: "a.com", kinds: [.camera, .microphone]) { _ in }
        #expect(browser.activePermissionRequest?.kinds == [.camera, .microphone])
    }

    @Test func siteControlsSwitchAnswersFutureRequests() {
        let (browser, tab) = makeBrowser()
        var decisions: [WKPermissionDecision] = []

        browser.setPermission(false, for: .camera, on: tab)
        browser.setPermission(true, for: .microphone, on: tab)
        browser.requestPermission(from: tab, origin: "meet.google.com", kinds: [.camera]) { decisions.append($0) }
        browser.requestPermission(from: tab, origin: "meet.google.com", kinds: [.microphone]) { decisions.append($0) }

        #expect(decisions == [.deny, .grant])
        #expect(browser.permissionRequests.isEmpty)
    }

    @Test func permissionOriginKeepsOnlyNonDefaultPorts() {
        #expect(URL(string: "https://meet.google.com/abc")!.permissionOrigin == "meet.google.com")
        #expect(URL(string: "https://example.com:443")!.permissionOrigin == "example.com")
        #expect(URL(string: "http://localhost:3000/")!.permissionOrigin == "localhost:3000")
    }

    @Test func closingTheTabDeniesItsPendingRequests() {
        let (browser, tab) = makeBrowser()
        var decisions: [WKPermissionDecision] = []

        browser.requestPermission(from: tab, origin: "a.com", kinds: [.camera]) { decisions.append($0) }
        browser.close(tab)
        #expect(decisions == [.deny])
        #expect(browser.permissionRequests.isEmpty)
    }

    @Test func externalLinksOpenInANewForegroundTab() {
        let (browser, _) = makeBrowser()
        browser.showCommandBar(.newTab)

        browser.openExternalURL(URL(string: "https://example.com")!)
        #expect(browser.activeTab?.url.host == "example.com")
        #expect(browser.todayTabs.count == 2)
        #expect(browser.commandBar == nil)
    }
}
