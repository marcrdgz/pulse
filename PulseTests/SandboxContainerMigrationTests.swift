import Foundation
import Testing
@testable import Pulse

struct SandboxContainerMigrationTests {
    private let bundleID = "dev.doblefilo.pulse"
    private let home = FileManager.default.temporaryDirectory.appending(path: "PulseTests-\(UUID().uuidString)")

    private func write(_ text: String, to path: String) throws {
        let url = home.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ path: String) -> String? {
        (try? Data(contentsOf: home.appending(path: path))).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func movesTheContainersDataAndSettingsOutOfTheSandbox() throws {
        let container = "Library/Containers/\(bundleID)/Data/Library"
        try write("session", to: "\(container)/Application Support/Pulse/session.json")
        try write("profile", to: "\(container)/WebKit/WebsiteDataStore/1234/Cookies")
        try write("cookies", to: "\(container)/HTTPStorages/\(bundleID)/httpstorages.sqlite")
        try write("legacy", to: "\(container)/Cookies/Cookies.binarycookies")
        try FileManager.default.createDirectory(at: home.appending(path: "\(container)/Preferences"), withIntermediateDirectories: true)
        try (["searchEngine": "duckduckgo"] as NSDictionary).write(to: home.appending(path: "\(container)/Preferences/\(bundleID).plist"))
        let defaults = try #require(UserDefaults(suiteName: "PulseTests-\(UUID().uuidString)"))

        SandboxContainerMigration.run(bundleID: bundleID, home: home, defaults: defaults)

        #expect(read("Library/Application Support/\(bundleID)/session.json") == "session")
        #expect(read("Library/WebKit/\(bundleID)/WebsiteDataStore/1234/Cookies") == "profile")
        #expect(read("Library/HTTPStorages/\(bundleID)/httpstorages.sqlite") == "cookies")
        #expect(read("Library/Cookies/\(bundleID).binarycookies") == "legacy")
        #expect(defaults.string(forKey: "searchEngine") == "duckduckgo")
        #expect(read("\(container)/Application Support/Pulse/session.json") == nil)

        try FileManager.default.removeItem(at: home)
    }

    @Test func leavesDataAlreadyOutsideTheSandboxAlone() throws {
        try write("old", to: "Library/Containers/\(bundleID)/Data/Library/Application Support/Pulse/session.json")
        try write("current", to: "Library/Application Support/\(bundleID)/session.json")
        let defaults = try #require(UserDefaults(suiteName: "PulseTests-\(UUID().uuidString)"))

        SandboxContainerMigration.run(bundleID: bundleID, home: home, defaults: defaults)

        #expect(read("Library/Application Support/\(bundleID)/session.json") == "current")

        try FileManager.default.removeItem(at: home)
    }
}
