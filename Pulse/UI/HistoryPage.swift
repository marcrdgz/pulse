import AppKit
import SwiftUI

/// The ⌘Y page, with Chrome's behavior: visits grouped by day, search, multi-select delete,
/// "More from this site" and a shortcut to clearing browsing data.
struct HistoryPage: View {
    @Environment(Browser.self) private var browser
    let tab: Tab
    @State private var query = ""
    @State private var visits: [HistoryVisit] = []
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
        .onChange(of: query) { reload() }
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

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(days, id: \.start) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(day.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                        VStack(spacing: 0) {
                            ForEach(day.visits) { visit in
                                HistoryRow(
                                    visit: visit,
                                    isSelected: selection.contains(visit.id),
                                    isSelecting: !selection.isEmpty,
                                    toggleSelection: { toggle(visit) },
                                    open: { inBackground in open(visit, inBackground: inBackground) },
                                    showMoreFromSite: { query = visit.url.displayHost ?? "" },
                                    remove: { browser.history?.deleteVisits([visit.id]) }
                                )
                            }
                        }
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    /// Visits arrive newest first, so days come out in order too.
    private var days: [Day] {
        var days: [Day] = []
        for visit in visits {
            let start = Calendar.current.startOfDay(for: visit.date)
            if days.last?.start == start {
                days[days.count - 1] = Day(start: start, visits: days[days.count - 1].visits + [visit])
            } else {
                days.append(Day(start: start, visits: [visit]))
            }
        }
        return days
    }

    private func reload() {
        visits = browser.history?.visits(matching: query) ?? []
        selection.formIntersection(visits.map(\.id))
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
            HistoryFavicon(url: visit.url)
            Text(visit.title.isEmpty ? visit.url.absoluteString : visit.title)
                .lineLimit(1)
                .layoutPriority(1)
            Text(visit.url.displayHost ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Button("More from This Site", action: showMoreFromSite)
                Button("Remove from History", action: remove)
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
    }
}

private struct HistoryFavicon: View {
    let url: URL
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "globe").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: 16, height: 16)
        .task(id: url.host()) {
            icon = await FaviconLoader.shared.favicon(forPage: url, declaredIconURL: nil)
        }
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
                        await BrowsingDataCleaner.clear(selection, in: range, history: browser.history)
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
