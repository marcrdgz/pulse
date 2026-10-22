import Foundation
import Testing
@testable import Pulse

struct DownloadManagerTests {
    @Test func numbersDestinationsInsteadOfOverwriting() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PulseDownloads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(DownloadManager.availableDestination(for: "report.pdf", in: directory).lastPathComponent == "report.pdf")

        FileManager.default.createFile(atPath: directory.appending(path: "report.pdf").path, contents: Data())
        FileManager.default.createFile(atPath: directory.appending(path: "report 2.pdf").path, contents: Data())
        #expect(DownloadManager.availableDestination(for: "report.pdf", in: directory).lastPathComponent == "report 3.pdf")

        FileManager.default.createFile(atPath: directory.appending(path: "LICENSE").path, contents: Data())
        #expect(DownloadManager.availableDestination(for: "LICENSE", in: directory).lastPathComponent == "LICENSE 2")
    }

    @Test func keepsDownloadsInsideTheDirectory() {
        let directory = URL(filePath: "/tmp/downloads", directoryHint: .isDirectory)
        #expect(DownloadManager.availableDestination(for: "../../etc/passwd", in: directory).path == "/tmp/downloads/passwd")
        #expect(DownloadManager.availableDestination(for: "", in: directory).lastPathComponent == "download")
    }
}

struct DownloadHistoryTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "PulseDownloadRecords-\(UUID().uuidString)")

    private func writeRecords(_ json: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Downloads.json")
        try Data(json.utf8).write(to: url)
        return url
    }

    @Test func remembersFinishedDownloadsAndMarksDeletedFiles() throws {
        let existing = directory.appending(path: "report.pdf")
        let recordsURL = try writeRecords("""
            [{"id":"\(UUID())","sourceURL":"https://a.com/report.pdf","startDate":0,"filename":"report.pdf",
              "destination":"\(existing.absoluteString)","totalBytes":2048,"outcome":"completed"},
             {"id":"\(UUID())","sourceURL":"https://a.com/gone.zip","startDate":0,"filename":"gone.zip",
              "destination":"\(directory.appending(path: "gone.zip").absoluteString)","totalBytes":10,"outcome":"completed"},
             {"id":"\(UUID())","sourceURL":"https://a.com/big.iso","startDate":0,"filename":"big.iso",
              "totalBytes":-1,"outcome":"failed","failureMessage":"Interrupted"}]
            """)
        FileManager.default.createFile(atPath: existing.path, contents: Data(count: 2048))
        defer { try? FileManager.default.removeItem(at: directory) }

        let manager = DownloadManager(directory: directory, recordsURL: recordsURL)
        let statuses = manager.downloads.map { DownloadStatus.text(for: $0) }
        #expect(statuses == ["2 KB", "Deleted", "Failed – Interrupted"])
        #expect(manager.activeDownloads.isEmpty)

        manager.clearFinished()
        #expect(DownloadManager(directory: directory, recordsURL: recordsURL).downloads.isEmpty)
    }
}

struct StartupTests {
    @Test func emptyTodayKeepsFavoritesAndPinnedTabs() throws {
        let store = SessionStore(fileURL: FileManager.default.temporaryDirectory
            .appending(path: "PulseStartup-\(UUID().uuidString)").appending(path: "session.json"))
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        let browser = Browser(sessionStore: store)
        browser.toggleFavorite(browser.openTab(url: URL(string: "https://fav.com")!))
        browser.togglePin(browser.openTab(url: URL(string: "https://pinned.com")!))
        browser.openTab(url: URL(string: "https://today.com")!)
        browser.saveSession()

        let preferences = Preferences()
        preferences.startupBehavior = .clearToday
        let restored = Browser(sessionStore: store, preferences: preferences)

        #expect(restored.todayTabs.isEmpty)
        #expect(restored.favorites.map(\.url.host) == ["fav.com"])
        #expect(restored.pinnedTabs.map(\.url.host) == ["pinned.com"])
        #expect(restored.activeTab == nil)
        #expect(Browser(sessionStore: store).todayTabs.map(\.url.host) == ["today.com"])
    }
}
