import SwiftUI

/// The ⌘⇧J page, like chrome://downloads: every download grouped by day, with search.
struct DownloadsPage: View {
    @Environment(Browser.self) private var browser
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var downloads: [Download] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return browser.downloads.downloads }
        return browser.downloads.downloads.filter {
            $0.filename.lowercased().contains(needle)
                || ($0.sourceURL?.absoluteString.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Downloads")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search downloads", text: $query)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                }
                .padding(.horizontal, 10)
                .frame(width: 320, height: 30)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button("Clear All", action: browser.downloads.clearFinished)
                    .disabled(!browser.downloads.downloads.contains { !$0.isActive })
            }
            .frame(height: 56)
            .padding(.horizontal, 20)
            Divider()
            if downloads.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 30, weight: .light))
                    Text(query.isEmpty ? "Files you download appear here" : "No results for “\(query)”")
                        .font(.system(size: 14))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(days, id: \.start) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(day.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 12)
                                VStack(spacing: 0) {
                                    ForEach(day.downloads) { DownloadRow(download: $0, isDetailed: true) }
                                }
                                .padding(4)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { isSearchFocused = true }
    }

    private struct Day {
        let start: Date
        let downloads: [Download]

        var title: String {
            let date = start.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
            if Calendar.current.isDateInToday(start) { return "Today – \(date)" }
            if Calendar.current.isDateInYesterday(start) { return "Yesterday – \(date)" }
            return date
        }
    }

    private var days: [Day] {
        var days: [Day] = []
        for download in downloads {
            let start = Calendar.current.startOfDay(for: download.startDate)
            if days.last?.start == start {
                days[days.count - 1] = Day(start: start, downloads: days[days.count - 1].downloads + [download])
            } else {
                days.append(Day(start: start, downloads: [download]))
            }
        }
        return days
    }
}
