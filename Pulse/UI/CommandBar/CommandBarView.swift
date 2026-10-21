import AppKit
import SwiftUI

enum CommandBarSuggestion {
    case open(URL)
    case search(query: String, url: URL)
    case switchTo(Tab)

    static let maxTabMatches = 6

    /// The typed destination first, then open tabs whose title or URL matches.
    static func suggestions(for query: String, openTabs: [Tab]) -> [CommandBarSuggestion] {
        var suggestions: [CommandBarSuggestion] = []
        switch AddressResolver.destination(for: query) {
        case .url(let url): suggestions.append(.open(url))
        case .search(let query, let url): suggestions.append(.search(query: query, url: url))
        case nil: break
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = openTabs.filter { tab in
            needle.isEmpty
                || tab.displayTitle.lowercased().contains(needle)
                || tab.url.absoluteString.lowercased().contains(needle)
        }
        suggestions += matches.prefix(maxTabMatches).map(CommandBarSuggestion.switchTo)
        return suggestions
    }
}

/// Arc's ⌘T / ⌘L palette: type a URL or search, or jump to an open tab.
struct CommandBarView: View {
    @Environment(Browser.self) private var browser
    let mode: CommandBarMode
    @State private var query: String
    @State private var selectedIndex = 0
    @State private var keyMonitor: Any?
    @FocusState private var isFieldFocused: Bool

    init(mode: CommandBarMode, initialQuery: String) {
        self.mode = mode
        _query = State(initialValue: initialQuery)
    }

    private var suggestions: [CommandBarSuggestion] {
        CommandBarSuggestion.suggestions(for: query, openTabs: browser.allTabs)
    }

    var body: some View {
        let suggestions = suggestions
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: mode == .newTab ? "plus.magnifyingglass" : "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                TextField("Search or Enter URL…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($isFieldFocused)
                    .onSubmit(submit)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)

            if !suggestions.isEmpty {
                Divider()
                VStack(spacing: 2) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        SuggestionRow(suggestion: suggestion, isSelected: index == selectedIndex)
                            .onTapGesture { perform(suggestion) }
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.15))
        )
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        .onAppear {
            isFieldFocused = true
            installKeyMonitor()
        }
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: query) { selectedIndex = 0 }
    }

    private func submit() {
        let suggestions = suggestions
        guard suggestions.indices.contains(selectedIndex) else { return }
        perform(suggestions[selectedIndex])
    }

    private func perform(_ suggestion: CommandBarSuggestion) {
        switch suggestion {
        case .open(let url), .search(_, let url): browser.open(url, from: mode)
        case .switchTo(let tab): browser.switchTo(tab)
        }
    }

    /// The focused text field's editor consumes arrow keys, so list navigation is handled at the event level.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case KeyCode.downArrow:
                selectedIndex = min(selectedIndex + 1, max(suggestions.count - 1, 0))
            case KeyCode.upArrow:
                selectedIndex = max(selectedIndex - 1, 0)
            case KeyCode.escape:
                browser.dismissCommandBar()
            default:
                return event
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private enum KeyCode {
        static let escape: UInt16 = 53
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
    }
}

private struct SuggestionRow: View {
    let suggestion: CommandBarSuggestion
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 16, height: 16)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(hint)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .opacity(isSelected ? 1 : 0)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        switch suggestion {
        case .open: Image(systemName: "globe")
        case .search: Image(systemName: "magnifyingglass")
        case .switchTo(let tab): FaviconView(tab: tab, size: 16)
        }
    }

    private var title: String {
        switch suggestion {
        case .open(let url): url.absoluteString
        case .search(let query, _): query
        case .switchTo(let tab): tab.displayTitle
        }
    }

    private var hint: String {
        switch suggestion {
        case .open: "Open"
        case .search: "Search Google"
        case .switchTo: "Switch to Tab"
        }
    }
}
