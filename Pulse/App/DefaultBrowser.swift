import AppKit
import OSLog

enum DefaultBrowser {
    static var isDefault: Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// macOS asks the user to confirm; setting the `http` handler makes Pulse the default web browser.
    static func makeDefault() async {
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")
        } catch {
            Logger(subsystem: "dev.doblefilo.pulse", category: "DefaultBrowser")
                .error("Couldn't become the default browser: \(error.localizedDescription, privacy: .public)")
        }
    }
}
