import AppKit
import Foundation
import Observation
import OSLog
import WebKit

@Observable
final class Download: Identifiable {
    enum State: Equatable {
        case inProgress
        case paused
        case completed
        case failed(String)
        case cancelled
    }

    let id: UUID
    let sourceURL: URL?
    let startDate: Date
    fileprivate(set) var filename: String
    fileprivate(set) var destination: URL?
    fileprivate(set) var state: State
    fileprivate(set) var receivedBytes: Int64
    /// `-1` while the server hasn't said.
    fileprivate(set) var totalBytes: Int64

    @ObservationIgnored fileprivate var task: WKDownload?
    @ObservationIgnored fileprivate var resumeData: Data?
    @ObservationIgnored fileprivate var progressObservations: [NSKeyValueObservation] = []

    fileprivate init(
        id: UUID = UUID(),
        sourceURL: URL?,
        startDate: Date = .now,
        filename: String,
        destination: URL? = nil,
        state: State = .inProgress,
        receivedBytes: Int64 = 0,
        totalBytes: Int64 = -1
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.startDate = startDate
        self.filename = filename
        self.destination = destination
        self.state = state
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
    }

    var isActive: Bool { state == .inProgress || state == .paused }

    var fractionCompleted: Double? {
        totalBytes > 0 ? min(Double(receivedBytes) / Double(totalBytes), 1) : nil
    }

    /// Chrome shows "Deleted" for finished downloads whose file is gone.
    var isFileMissing: Bool {
        state == .completed && !(destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
    }

    /// Based on the average speed so far; `nil` until there's enough to estimate.
    func estimatedTimeRemaining(now: Date = .now) -> TimeInterval? {
        let elapsed = now.timeIntervalSince(startDate)
        guard state == .inProgress, totalBytes > 0, receivedBytes > 0, elapsed > 1 else { return nil }
        let speed = Double(receivedBytes) / elapsed
        return Double(totalBytes - receivedBytes) / speed
    }
}

/// Saves WebKit downloads and keeps Chrome's download list: progress, pause/resume, cancel,
/// retry, and finished downloads remembered across launches.
@Observable
final class DownloadManager: NSObject, WKDownloadDelegate {
    /// Newest first.
    private(set) var downloads: [Download] = []

    @ObservationIgnored weak var browser: Browser?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let recordsURL: URL?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var downloadsByTask: [ObjectIdentifier: Download] = [:]
    /// Retries and resumes need a web view; this one shares cookies with every tab.
    @ObservationIgnored private lazy var backgroundWebView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

    init(directory: URL = .downloadsDirectory, recordsURL: URL? = nil, preferences: Preferences = Preferences()) {
        self.directory = directory
        self.recordsURL = recordsURL
        self.preferences = preferences
        super.init()
        downloads = loadRecords()
    }

    var activeDownloads: [Download] { downloads.filter(\.isActive) }

    /// Overall progress of running downloads, for the sidebar button's ring.
    var activeProgress: Double? {
        let running = activeDownloads.filter { $0.totalBytes > 0 }
        guard !running.isEmpty else { return nil }
        let total = running.reduce(Int64(0)) { $0 + $1.totalBytes }
        return Double(running.reduce(Int64(0)) { $0 + $1.receivedBytes }) / Double(total)
    }

    // MARK: Actions

    func track(_ task: WKDownload) {
        let download = Download(sourceURL: task.originalRequest?.url, filename: task.originalRequest?.url?.lastPathComponent ?? "download")
        downloads.insert(download, at: 0)
        attach(task, to: download)
        browser?.downloadDidStart(download)
    }

    func cancel(_ download: Download) {
        guard download.isActive else { return }
        download.task?.cancel()
        finish(download, as: .cancelled)
        if let destination = download.destination { try? FileManager.default.removeItem(at: destination) }
    }

    func pause(_ download: Download) {
        guard download.state == .inProgress, let task = download.task else { return }
        download.state = .paused
        task.cancel { [weak download] resumeData in
            download?.resumeData = resumeData
        }
    }

    func resume(_ download: Download) {
        guard download.state == .paused else { return }
        guard let resumeData = download.resumeData else {
            retry(download)
            return
        }
        download.state = .inProgress
        backgroundWebView.resumeDownload(fromResumeData: resumeData) { [weak self, weak download] task in
            guard let self, let download else { return }
            self.attach(task, to: download)
        }
    }

    /// Starts failed or cancelled downloads again from their original address.
    func retry(_ download: Download) {
        guard let sourceURL = download.sourceURL else { return }
        download.state = .inProgress
        download.receivedBytes = 0
        download.resumeData = nil
        backgroundWebView.startDownload(using: URLRequest(url: sourceURL)) { [weak self, weak download] task in
            guard let self, let download else { return }
            self.attach(task, to: download)
        }
    }

    func open(_ download: Download) {
        guard download.state == .completed, let destination = download.destination, !download.isFileMissing else { return }
        NSWorkspace.shared.open(destination)
    }

    func showInFinder(_ download: Download) {
        guard let destination = download.destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// Removes the entry, not the file.
    func remove(_ download: Download) {
        if download.isActive { cancel(download) }
        downloads.removeAll { $0.id == download.id }
        saveRecords()
    }

    func clearFinished() {
        downloads.removeAll { !$0.isActive }
        saveRecords()
    }

    // MARK: WKDownloadDelegate

    func download(
        _ task: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        guard let download = downloadsByTask[ObjectIdentifier(task)] else { return nil }
        if response.expectedContentLength > 0 { download.totalBytes = response.expectedContentLength }

        let destination: URL?
        if preferences.asksWhereToSaveDownloads {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFilename
            panel.directoryURL = directory
            destination = panel.runModal() == .OK ? panel.url : nil
            // The save panel already asked about replacing an existing file.
            if let destination { try? FileManager.default.removeItem(at: destination) }
        } else {
            destination = Self.availableDestination(for: suggestedFilename, in: directory)
        }

        guard let destination else {
            finish(download, as: .cancelled)
            return nil
        }
        download.destination = destination
        download.filename = destination.lastPathComponent
        return destination
    }

    func downloadDidFinish(_ task: WKDownload) {
        guard let download = downloadsByTask[ObjectIdentifier(task)] else { return }
        download.receivedBytes = max(download.receivedBytes, download.totalBytes)
        finish(download, as: .completed)
        if let destination = download.destination {
            // Bounces the Dock's Downloads stack, like Safari does.
            DistributedNotificationCenter.default().post(
                name: Notification.Name("com.apple.DownloadFileFinished"),
                object: destination.path
            )
        }
    }

    func download(_ task: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let download = downloadsByTask[ObjectIdentifier(task)] else { return }
        // Pausing cancels the task; that "failure" is expected.
        if download.state == .paused || download.state == .cancelled {
            downloadsByTask[ObjectIdentifier(task)] = nil
            return
        }
        download.resumeData = resumeData
        Logger.downloads.error("Download failed: \(error.localizedDescription, privacy: .public)")
        finish(download, as: .failed(error.localizedDescription))
    }

    // MARK: Helpers

    private func attach(_ task: WKDownload, to download: Download) {
        task.delegate = self
        download.task = task
        downloadsByTask[ObjectIdentifier(task)] = download
        let progress = task.progress
        download.progressObservations = [
            progress.observe(\.completedUnitCount) { [weak download] progress, _ in
                let received = progress.completedUnitCount
                MainActor.assumeIsolated { download?.receivedBytes = received }
            },
            progress.observe(\.totalUnitCount) { [weak download] progress, _ in
                let total = progress.totalUnitCount
                MainActor.assumeIsolated { if total > 0 { download?.totalBytes = total } }
            },
        ]
    }

    private func finish(_ download: Download, as state: Download.State) {
        download.state = state
        download.progressObservations = []
        if let task = download.task { downloadsByTask[ObjectIdentifier(task)] = nil }
        download.task = nil
        saveRecords()
        browser?.downloadDidFinish(download)
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

    // MARK: Persistence

    private struct Record: Codable {
        var id: UUID
        var sourceURL: URL?
        var startDate: Date
        var filename: String
        var destination: URL?
        var totalBytes: Int64
        var outcome: String
        var failureMessage: String?
    }

    /// Only finished downloads are remembered; interrupted ones come back as failed.
    private func saveRecords() {
        guard let recordsURL else { return }
        let records = downloads.prefix(200).map { download in
            let (outcome, message): (String, String?) = switch download.state {
            case .completed: ("completed", nil)
            case .cancelled: ("cancelled", nil)
            case .failed(let message): ("failed", message)
            case .inProgress, .paused: ("failed", "Interrupted")
            }
            return Record(
                id: download.id,
                sourceURL: download.sourceURL,
                startDate: download.startDate,
                filename: download.filename,
                destination: download.destination,
                totalBytes: download.totalBytes,
                outcome: outcome,
                failureMessage: message
            )
        }
        do {
            try FileManager.default.createDirectory(at: recordsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Array(records)).write(to: recordsURL, options: .atomic)
        } catch {
            Logger.downloads.error("Couldn't save downloads: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadRecords() -> [Download] {
        guard let recordsURL, let data = try? Data(contentsOf: recordsURL),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        return records.map { record in
            let state: Download.State = switch record.outcome {
            case "completed": .completed
            case "cancelled": .cancelled
            default: .failed(record.failureMessage ?? "Failed")
            }
            return Download(
                id: record.id,
                sourceURL: record.sourceURL,
                startDate: record.startDate,
                filename: record.filename,
                destination: record.destination,
                state: state,
                receivedBytes: state == .completed ? record.totalBytes : 0,
                totalBytes: record.totalBytes
            )
        }
    }
}

private extension Logger {
    static let downloads = Logger(subsystem: "dev.doblefilo.pulse", category: "Downloads")
}
