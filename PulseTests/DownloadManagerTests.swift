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
