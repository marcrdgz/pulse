import Foundation
import os

extension URL {
    /// Where Pulse keeps its session, history, downloads and extensions. Keyed by bundle ID so Pulse Dev
    /// never touches the installed browser's data, and so it can't collide with other apps named Pulse.
    static var pulseSupportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "dev.doblefilo.pulse", directoryHint: .isDirectory)
    }
}

/// Pulse used to be sandboxed, so an update finds everything in the old app container. This moves it
/// to where the unsandboxed app looks, keeping the session, history, settings, profiles and sign-ins.
/// Caches stay behind; they rebuild on their own.
enum SandboxContainerMigration {
    /// Must run before anything reads the defaults or creates a WebKit data store, which would start
    /// out empty and then refuse to be replaced.
    static func run(bundleID: String, home: URL, defaults: UserDefaults) {
        let container = home.appending(path: "Library/Containers/\(bundleID)/Data/Library", directoryHint: .isDirectory)
        let library = home.appending(path: "Library", directoryHint: .isDirectory)
        let oldSupport = container.appending(path: "Application Support/Pulse", directoryHint: .isDirectory)
        let newSupport = library.appending(path: "Application Support/\(bundleID)", directoryHint: .isDirectory)
        // The support folder moves last, so its absence marks a migration that hasn't finished.
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: oldSupport.path), !fileManager.fileExists(atPath: newSupport.path) else { return }

        if let preferences = NSDictionary(contentsOf: container.appending(path: "Preferences/\(bundleID).plist")) as? [String: Any] {
            for (key, value) in preferences { defaults.set(value, forKey: key) }
        }
        // Inside the container WebKit's folders aren't keyed by bundle ID; outside they are.
        let moves = [
            ("WebKit", "WebKit/\(bundleID)"),
            ("HTTPStorages/\(bundleID)", "HTTPStorages/\(bundleID)"),
            ("Cookies/Cookies.binarycookies", "Cookies/\(bundleID).binarycookies"),
        ].map { (container.appending(path: $0), library.appending(path: $1)) } + [(oldSupport, newSupport)]
        for (source, destination) in moves where fileManager.fileExists(atPath: source.path) {
            do {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                Logger.migration.error("Couldn't move \(source.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private extension Logger {
    static let migration = Logger(subsystem: "dev.doblefilo.pulse", category: "Migration")
}
