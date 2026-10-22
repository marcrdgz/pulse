import Foundation
import OSLog
import WebKit

/// Saves WebKit downloads into ~/Downloads and reports them through the browser's toast.
final class DownloadManager: NSObject, WKDownloadDelegate {
    weak var browser: Browser?
    private let directory: URL
    private var destinations: [ObjectIdentifier: URL] = [:]

    init(directory: URL = .downloadsDirectory) {
        self.directory = directory
    }

    func track(_ download: WKDownload) {
        Logger.downloads.debug("Started \(download.originalRequest?.url?.absoluteString ?? "?", privacy: .public)")
        download.delegate = self
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        let destination = Self.availableDestination(for: suggestedFilename, in: directory)
        destinations[ObjectIdentifier(download)] = destination
        browser?.showToast("Downloading \(destination.lastPathComponent)…")
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        // Bounces the Dock's Downloads stack, like Safari does.
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.apple.DownloadFileFinished"),
            object: destination.path
        )
        browser?.showToast("Downloaded \(destination.lastPathComponent)")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let destination = destinations.removeValue(forKey: ObjectIdentifier(download))
        Logger.downloads.error("Download failed: \(error.localizedDescription, privacy: .public)")
        browser?.showToast("Couldn't download \(destination?.lastPathComponent ?? "file")")
    }

    /// `report.pdf`, then `report 2.pdf`, `report 3.pdf`… so existing files are never overwritten.
    static func availableDestination(for suggestedFilename: String, in directory: URL) -> URL {
        let filename = (suggestedFilename as NSString).lastPathComponent
        let name = filename.isEmpty ? "download" : filename
        let base = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension

        var candidate = directory.appending(path: name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(base) \(counter)"
            candidate = directory.appending(path: pathExtension.isEmpty ? numbered : "\(numbered).\(pathExtension)")
            counter += 1
        }
        return candidate
    }
}

private extension Logger {
    static let downloads = Logger(subsystem: "dev.doblefilo.pulse", category: "Downloads")
}
