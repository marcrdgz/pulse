import Foundation
import OSLog
import Testing
@testable import Pulse

struct ProblemReportTests {
    @Test func describesTheSessionWithoutRevealingBrowsing() {
        let browser = Browser()
        browser.openTab(url: URL(string: "https://secret-bank.example/account")!)
        browser.openTab(url: URL(string: "https://swift.org")!)
        browser.togglePin(browser.todayTabs[0])

        let text = ProblemReport(browser: browser, log: ["2026-10-23T10:00:00Z error [Session] Failed to save"]).text

        #expect(text.contains("Spaces: 1"))
        #expect(text.contains("1 pinned, 1 today"))
        #expect(text.contains("[Session] Failed to save"))
        #expect(!text.contains("secret-bank"))
        #expect(!text.contains("swift.org"))
        #expect(!text.contains("Home"))
    }

    @Test func prefillsTheBugReportForm() throws {
        let report = ProblemReport(browser: Browser(), log: [])
        let items = try #require(URLComponents(url: report.issueURL, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(report.issueURL.path() == "/marcrdgz/pulse/issues/new")
        #expect(items.contains(URLQueryItem(name: "template", value: "bug_report.yml")))
        #expect(items.contains(URLQueryItem(name: "version", value: report.appVersion)))
        #expect(items.contains(URLQueryItem(name: "macos", value: report.macOSVersion)))
    }

    @Test func readsPulsesOwnLogFromThisLaunch() {
        let marker = UUID().uuidString
        Logger(subsystem: ProblemReport.logSubsystem, category: "Tests").error("Problem report \(marker, privacy: .public)")

        #expect(ProblemReport.recentLog().contains { $0.contains("error [Tests] Problem report \(marker)") })
    }
}
