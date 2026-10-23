import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar's downloads button: a progress ring while something downloads, and Chrome's
/// download bubble on click (it also opens by itself when a download starts).
struct DownloadsButton: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        @Bindable var browser = browser
        Button { browser.isDownloadsBubblePresented.toggle() } label: {
            ZStack {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                Circle()
                    .stroke(Theme.sidebarText.opacity(0.25), lineWidth: 1.5)
                if let progress = browser.downloads.activeProgress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.2), value: progress)
                }
            }
            .frame(width: 16, height: 16)
        }
        .buttonStyle(SidebarIconButtonStyle())
        .help("Downloads (⌘⇧J)")
        .accessibilityLabel("Downloads")
        .popover(isPresented: $browser.isDownloadsBubblePresented, arrowEdge: .top) {
            DownloadsBubble()
                .environment(browser)
        }
    }
}

private struct DownloadsBubble: View {
    @Environment(Browser.self) private var browser

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Downloads")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                ForEach(browser.downloads.downloads.prefix(5)) { download in
                    DownloadRow(download: download)
                }
            }
            .padding(.horizontal, 4)
            Divider()
                .padding(.top, 4)
            Button("Show All Downloads", action: browser.showDownloads)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 360)
    }
}

/// One download, with Chrome's actions for its state; clicking a finished one opens the file.
struct DownloadRow: View {
    @Environment(Browser.self) private var browser
    let download: Download
    /// The downloads page also shows where it came from and lets you remove the entry.
    var isDetailed = false
    @State private var isHovered = false

    private var manager: DownloadManager { browser.downloads }

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(download: download)
            VStack(alignment: .leading, spacing: 3) {
                Text(download.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .strikethrough(download.isFileMissing || download.state == .cancelled)
                if download.isActive {
                    ProgressView(value: download.fractionCompleted ?? 0)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .opacity(download.fractionCompleted == nil ? 0.4 : 1)
                }
                Text(DownloadStatus.text(for: download))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isDetailed, let source = download.sourceURL {
                    Text(source.absoluteString)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            actions
                .buttonStyle(SidebarIconButtonStyle())
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { manager.open(download) }
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var contextMenu: some View {
        let isFileAvailable = download.state == .completed && !download.isFileMissing
        Button("Open") { manager.open(download) }
            .disabled(!isFileAvailable)
        Button("Show in Finder") { manager.showInFinder(download) }
            .disabled(!isFileAvailable)
        switch download.state {
        case .inProgress:
            Button("Pause") { manager.pause(download) }
            Button("Cancel") { manager.cancel(download) }
        case .paused:
            Button("Resume") { manager.resume(download) }
            Button("Cancel") { manager.cancel(download) }
        case .failed, .cancelled:
            Button("Retry") { manager.retry(download) }
                .disabled(download.sourceURL == nil)
        case .completed:
            EmptyView()
        }
        Divider()
        if let source = download.sourceURL {
            Button("Copy Download Link") { browser.copyLink(source) }
        }
        Button("Remove from List") { manager.remove(download) }
    }

    @ViewBuilder private var actions: some View {
        switch download.state {
        case .inProgress:
            action("pause.fill", "Pause") { manager.pause(download) }
            action("xmark", "Cancel") { manager.cancel(download) }
        case .paused:
            action("play.fill", "Resume") { manager.resume(download) }
            action("xmark", "Cancel") { manager.cancel(download) }
        case .completed:
            if !download.isFileMissing {
                action("magnifyingglass", "Show in Finder") { manager.showInFinder(download) }
            }
            if isDetailed { action("trash", "Remove from List") { manager.remove(download) } }
        case .failed, .cancelled:
            if download.sourceURL != nil {
                action("arrow.clockwise", "Retry") { manager.retry(download) }
            }
            if isDetailed { action("trash", "Remove from List") { manager.remove(download) } }
        }
    }

    private func action(_ symbol: String, _ help: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct FileIcon: View {
    let download: Download

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 32, height: 32)
            .opacity(download.state == .completed && !download.isFileMissing ? 1 : 0.6)
    }

    private var icon: NSImage {
        if let destination = download.destination, FileManager.default.fileExists(atPath: destination.path) {
            return NSWorkspace.shared.icon(forFile: destination.path)
        }
        let type = UTType(filenameExtension: (download.filename as NSString).pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}

enum DownloadStatus {
    /// Chrome's wording: "2.1 MB of 10 MB, 5 secs left", "Failed – Network error", "Deleted"…
    static func text(for download: Download, now: Date = .now) -> String {
        let received = bytes(download.receivedBytes)
        let progress = download.totalBytes > 0 ? "\(received) of \(bytes(download.totalBytes))" : received
        switch download.state {
        case .inProgress:
            guard let remaining = download.estimatedTimeRemaining(now: now),
                  let left = timeFormatter.string(from: remaining)
            else { return progress }
            return "\(progress), \(left) left"
        case .paused:
            return "Paused – \(progress)"
        case .completed:
            return download.isFileMissing ? "Deleted" : bytes(download.totalBytes > 0 ? download.totalBytes : download.receivedBytes)
        case .failed(let message):
            return "Failed – \(message)"
        case .cancelled:
            return "Cancelled"
        }
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(count, 0), countStyle: .file)
    }

    private static let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter
    }()
}
