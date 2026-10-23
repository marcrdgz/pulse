import AppKit
import OSLog

/// The diagnostics a user attaches to a GitHub bug report: versions, the shape of their session
/// and Pulse's log since launch. It leaves out URLs, page titles and space names, since it's posted
/// publicly; the log's private values are already redacted by the system.
struct ProblemReport {
    static let repository = URL(string: "https://github.com/marcrdgz/pulse")!
    /// Every `Logger` in Pulse uses it, in Debug builds too, whose bundle ID differs.
    static let logSubsystem = "dev.doblefilo.pulse"

    let createdAt: Date
    let appVersion: String
    let macOSVersion: String
    let webKitVersion: String
    let spaceCount: Int
    let favoriteCount: Int
    let pinnedCount: Int
    let todayCount: Int
    let sleepingCount: Int
    let extensionNames: [String]
    let blocksAdsAndTrackers: Bool
    let filterListsUpdated: Date?
    let log: [String]

    init(browser: Browser, log: [String], createdAt: Date = .now) {
        self.createdAt = createdAt
        let info = Bundle.main.infoDictionary ?? [:]
        appVersion = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        webKitVersion = Bundle(identifier: "com.apple.WebKit")?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        spaceCount = browser.spaces.count
        favoriteCount = browser.favorites.count
        pinnedCount = browser.spaces.map(\.pinnedTabs.count).reduce(0, +)
        todayCount = browser.spaces.map(\.todayTabs.count).reduce(0, +)
        sleepingCount = browser.everyTab.filter(\.isHibernated).count
        extensionNames = (browser.extensions?.contexts ?? [])
            .map { $0.webExtension.displayName ?? $0.uniqueIdentifier }
            .sorted()
        blocksAdsAndTrackers = browser.contentBlocker.isEnabled
        filterListsUpdated = browser.contentBlocker.lastUpdate
        self.log = log
    }

    var filename: String {
        "Pulse Problem Report \(createdAt.formatted(.iso8601.year().month().day())).txt"
    }

    var text: String {
        #if arch(arm64)
        let architecture = "Apple silicon"
        #else
        let architecture = "Intel"
        #endif
        return """
        Pulse problem report, \(createdAt.ISO8601Format())

        Pulse \(appVersion)
        macOS \(macOSVersion), \(architecture)
        WebKit \(webKitVersion)

        Spaces: \(spaceCount)
        Tabs: \(favoriteCount) favorites, \(pinnedCount) pinned, \(todayCount) today, \(sleepingCount) sleeping
        Ad and tracker blocking: \(blocksAdsAndTrackers ? "on" : "off"), \
        filter lists updated \(filterListsUpdated?.ISO8601Format() ?? "never")
        Extensions: \(extensionNames.isEmpty ? "none" : extensionNames.joined(separator: ", "))

        Log since launch:
        \(log.isEmpty ? "(empty)" : log.joined(separator: "\n"))

        """
    }

    /// GitHub's bug report form with the environment fields filled in.
    var issueURL: URL {
        var components = URLComponents(url: Self.repository.appending(path: "issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "version", value: appVersion),
            URLQueryItem(name: "macos", value: macOSVersion),
        ]
        return components.url!
    }

    /// Pulse's own entries from this launch; the system keeps no earlier ones for a sandboxed app to read.
    static func recentLog(limit: Int = 500) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", logSubsystem))
            let lines = entries.compactMap { $0 as? OSLogEntryLog }.map { entry in
                "\(entry.date.ISO8601Format()) \(entry.level.name) [\(entry.category)] \(entry.composedMessage)"
            }
            return Array(lines.suffix(limit))
        } catch {
            return ["Couldn't read the log: \(error.localizedDescription)"]
        }
    }

    /// Saves the report where the user picks, opens the bug report form in a new tab and shows the
    /// file in Finder, ready to drag into the form.
    static func file(from browser: Browser) {
        let report = ProblemReport(browser: browser, log: recentLog())
        let panel = NSSavePanel()
        panel.nameFieldStringValue = report.filename
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = .downloadsDirectory
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try report.text.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        browser.openTab(url: report.issueURL)
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }
}

private extension OSLogEntryLog.Level {
    var name: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "log"
        }
    }
}
