import AppKit
import SwiftUI

/// The ⌘Y page, with Chrome's behavior: visits grouped by day, search, multi-select delete,
/// "More from this site" and a shortcut to clearing browsing data.
struct HistoryPage: View {
    @Environment(Browser.self) private var browser
    let tab: Tab
    @State private var query = ""
    @State private var visits: [HistoryVisit] = []
    @State private var days: [Day] = []
    /// Grows a page at a time as the list scrolls to its end, so opening the page stays cheap.
    @State private var limit = Self.pageSize
    @State private var selection: Set<HistoryVisit.ID> = []
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .frame(height: 56)
                .padding(.horizontal, 20)
            Divider()
            if visits.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            reload()
            isSearchFocused = true
        }
        .onChange(of: query) {
            limit = Self.pageSize
            reload()
        }
        .onChange(of: browser.history?.revision) { reload() }
    }

    @ViewBuilder private var toolbar: some View {
        if selection.isEmpty {
            HStack(spacing: 16) {
                Text("History")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search history", text: $query)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(width: 320, height: 30)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button("Clear Browsing Data…", action: browser.showClearBrowsingData)
            }
        } else {
            HStack(spacing: 12) {
                Text("\(selection.count) selected")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Button("Cancel") { selection = [] }
                    .keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive, action: deleteSelection)
                    .keyboardShortcut(.delete, modifiers: [])
            }
        }
    }

    /// Days and their rows share one lazy stack so only the rows on screen get built; a day can
    /// hold hundreds of visits.
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days, id: \.start) { day in
                    Section {
                        ForEach(day.visits) { visit in
                            HistoryRow(
                                visit: visit,
                                isSelected: selection.contains(visit.id),
                                isSelecting: !selection.isEmpty,
                                toggleSelection: { toggle(visit) },
                                open: { inBackground in open(visit, inBackground: inBackground) },
                                copyLink: { browser.copyLink(visit.url) },
                                showMoreFromSite: { query = visit.url.displayHost ?? "" },
                                remove: { browser.history?.deleteVisits([visit.id]) }
                            )
                            .padding(.top, visit.id == day.visits.first?.id ? 4 : 0)
                            .padding(.bottom, visit.id == day.visits.last?.id ? 4 : 0)
                            .background(.quaternary.opacity(0.35), in: dayBackgroundShape(for: visit, in: day))
                            .onAppear {
                                if visit.id == visits.last?.id { loadMore() }
                            }
                        }
                    } header: {
                        Text(day.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                            .padding(.top, day.start == days.first?.start ? 0 : 20)
                            .padding(.bottom, 6)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: browser.history == nil ? "exclamationmark.triangle" : "clock")
                .font(.system(size: 30, weight: .light))
            Text(emptyMessage)
                .font(.system(size: 14))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if browser.history == nil { return "History isn't available" }
        return query.isEmpty ? "Pages you visit will appear here" : "No results for “\(query)”"
    }

    /// Rounds the outer corners of a day's first and last rows, so the day reads as one card.
    private func dayBackgroundShape(for visit: HistoryVisit, in day: Day) -> UnevenRoundedRectangle {
        let top: CGFloat = visit.id == day.visits.first?.id ? 10 : 0
        let bottom: CGFloat = visit.id == day.visits.last?.id ? 10 : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
    }

    private struct Day {
        let start: Date
        let visits: [HistoryVisit]

        var title: String {
            let date = start.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
            if Calendar.current.isDateInToday(start) { return "Today – \(date)" }
            if Calendar.current.isDateInYesterday(start) { return "Yesterday – \(date)" }
            return date
        }
    }

    private static let pageSize = 200

    /// Visits arrive newest first, so days come out in order too.
    private static func groupByDay(_ visits: [HistoryVisit]) -> [Day] {
        var days: [Day] = []
        var start: Date?
        var dayVisits: [HistoryVisit] = []
        for visit in visits {
            let visitDay = Calendar.current.startOfDay(for: visit.date)
            if let start, visitDay != start {
                days.append(Day(start: start, visits: dayVisits))
                dayVisits = []
            }
            start = visitDay
            dayVisits.append(visit)
        }
        if let start {
            days.append(Day(start: start, visits: dayVisits))
        }
        return days
    }

    private func reload() {
        visits = browser.history?.visits(matching: query, limit: limit) ?? []
        days = Self.groupByDay(visits)
        selection.formIntersection(visits.map(\.id))
    }

    /// A full page means there may be older visits to fetch.
    private func loadMore() {
        guard visits.count == limit else { return }
        limit += Self.pageSize
        reload()
    }

    private func toggle(_ visit: HistoryVisit) {
        if selection.contains(visit.id) {
            selection.remove(visit.id)
        } else {
            selection.insert(visit.id)
        }
    }

    private func deleteSelection() {
        browser.history?.deleteVisits(Array(selection))
        selection = []
    }

    /// Like Chrome: a click opens the page in this tab, ⌘-click in a background tab.
    private func open(_ visit: HistoryVisit, inBackground: Bool) {
        if inBackground {
            browser.openTab(url: visit.url, activate: false)
        } else {
            tab.load(visit.url)
        }
    }
}

private struct HistoryRow: View {
    let visit: HistoryVisit
    let isSelected: Bool
    let isSelecting: Bool
    let toggleSelection: () -> Void
    let open: (_ inBackground: Bool) -> Void
    let copyLink: () -> Void
    let showMoreFromSite: () -> Void
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Select", isOn: Binding(get: { isSelected }, set: { _ in toggleSelection() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .opacity(isSelecting || isHovered || isSelected ? 1 : 0)
            Text(visit.date, format: .dateTime.hour().minute())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            URLFavicon(url: visit.url)
            Text(visit.title.isEmpty ? visit.url.absoluteString : visit.title)
                .lineLimit(1)
                .layoutPriority(1)
            Text(visit.url.displayHost ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(isHovered ? 1 : 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(isHovered ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if isSelecting {
                toggleSelection()
            } else {
                open(NSEvent.modifierFlags.contains(.command))
            }
        }
        .help(visit.url.absoluteString)
        .contextMenu { menuItems }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Open in New Tab") { open(true) }
        Button("Copy Link", action: copyLink)
        Divider()
        Button("More from This Site", action: showMoreFromSite)
        Button("Remove from History", action: remove)
    }
}

/// Chrome's "Clear browsing data" dialog.
struct ClearBrowsingDataView: View {
    @Environment(Browser.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State private var range: BrowsingDataRange = .lastHour
    @State private var selection = BrowsingDataSelection()
    @State private var isClearing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Clear Browsing Data")
                .font(.system(size: 17, weight: .semibold))
            Picker("Time range", selection: $range) {
                ForEach(BrowsingDataRange.allCases) { Text($0.title).tag($0) }
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $selection.history) {
                    label("Browsing history", "Clears history from the address bar and the History page")
                }
                Toggle(isOn: $selection.cookies) {
                    label("Cookies and other site data", "Signs you out of most sites")
                }
                Toggle(isOn: $selection.cache) {
                    label("Cached images and files", "Some sites may load more slowly on your next visit")
                }
            }
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clear Data") {
                    isClearing = true
                    Task {
                        await BrowsingDataCleaner.clear(selection, in: range, history: browser.history, dataStores: browser.allDataStores)
                        browser.showToast("Browsing data cleared")
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isClearing || !(selection.history || selection.cookies || selection.cache))
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
