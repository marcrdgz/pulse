import AppKit
import SwiftUI

/// The ⌘T / ⌘L address bar, with Chrome's omnibox behavior in an Arc-style floating panel.
struct CommandBarView: View {
    @Environment(Browser.self) private var browser
    let mode: CommandBarMode
    @State private var text: String
    /// ⌘L opens with the current address selected; suggestions wait until it's edited.
    @State private var hasEdited = false
    @State private var allowsInlineCompletion = true
    @State private var searchSuggestions: [String] = []
    @State private var selectedIndex = 0

    init(mode: CommandBarMode, initialQuery: String) {
        self.mode = mode
        _text = State(initialValue: initialQuery)
    }

    private var result: OmniboxResult {
        guard hasEdited || mode == .newTab else { return OmniboxResult(suggestions: [], inlineCompletion: nil) }
        _ = browser.history?.revision
        return Omnibox.result(
            for: text,
            history: browser.history?.entries(matching: text) ?? [],
            openTabs: browser.everyTab,
            searchSuggestions: searchSuggestions,
            allowsInlineCompletion: allowsInlineCompletion,
            searchEngine: browser.preferences.searchEngine
        )
    }

    var body: some View {
        let result = result
        let suggestions = result.suggestions
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: mode == .newTab ? "plus.magnifyingglass" : "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                OmniboxField(
                    text: $text,
                    displayOverride: selectedIndex > 0 && suggestions.indices.contains(selectedIndex)
                        ? suggestions[selectedIndex].fillText : nil,
                    inlineCompletion: result.inlineCompletion,
                    placeholder: "Search or Enter URL…",
                    selectsAllInitially: mode == .editActiveTab,
                    onUserEdit: { isDeletion in
                        hasEdited = true
                        allowsInlineCompletion = !isDeletion
                        selectedIndex = 0
                    },
                    onCommand: { handle($0, result: result) }
                )
            }
            .padding(.horizontal, 18)
            .frame(height: 58)

            if !suggestions.isEmpty {
                Divider()
                VStack(spacing: 2) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            isSelected: index == selectedIndex,
                            remove: removeAction(for: suggestion)
                        )
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
        .task(id: text) { await loadSearchSuggestions() }
    }

    private func handle(_ command: OmniboxCommand, result: OmniboxResult) -> Bool {
        let suggestions = result.suggestions
        switch command {
        case .moveDown:
            selectedIndex = min(selectedIndex + 1, max(suggestions.count - 1, 0))
        case .moveUp:
            selectedIndex = max(selectedIndex - 1, 0)
        case .submit:
            if suggestions.indices.contains(selectedIndex) {
                perform(suggestions[selectedIndex])
            }
        case .cancel:
            browser.dismissCommandBar()
        case .acceptCompletion:
            guard let completion = result.inlineCompletion else { return false }
            text = completion
            selectedIndex = 0
        case .deleteSuggestion:
            guard suggestions.indices.contains(selectedIndex),
                  let remove = removeAction(for: suggestions[selectedIndex])
            else { return false }
            remove()
            selectedIndex = 0
        }
        return true
    }

    /// History suggestions can be removed from history, like Chrome's ⇧⌦ or the row's ✕.
    private func removeAction(for suggestion: OmniboxSuggestion) -> (() -> Void)? {
        guard case .navigate(let url, let title) = suggestion, title != nil, let history = browser.history
        else { return nil }
        return { history.deleteURL(url) }
    }

    private func perform(_ suggestion: OmniboxSuggestion) {
        switch suggestion {
        // Addresses picked in the omnibox count as typed, which ranks them higher next time.
        case .navigate(let url, _): browser.open(url, from: mode, isTyped: true)
        case .search(_, let url): browser.open(url, from: mode)
        case .switchTo(let tab): browser.switchTo(tab)
        }
    }

    private func loadSearchSuggestions() async {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard hasEdited, !query.isEmpty, browser.preferences.showsSearchSuggestions else {
            searchSuggestions = []
            return
        }
        // Debounce typing; a new keystroke cancels this task.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let suggestions = await SearchSuggestions.fetch(for: query, from: browser.preferences.searchEngine)
        guard !Task.isCancelled else { return }
        searchSuggestions = suggestions
    }
}

private struct SuggestionRow: View {
    @Environment(Browser.self) private var browser
    let suggestion: OmniboxSuggestion
    let isSelected: Bool
    let remove: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 16, height: 16)
            HStack(spacing: 0) {
                Text(title)
                    .lineLimit(1)
                if let detail {
                    Text(" – \(detail)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let remove, isHovered || isSelected {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(SidebarIconButtonStyle())
                .help("Remove from History (⇧⌦)")
            } else if let hint {
                Text(hint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(isSelected || isTabSwitch ? 1 : 0)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : isHovered ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var isTabSwitch: Bool {
        if case .switchTo = suggestion { return true }
        return false
    }

    @ViewBuilder private var icon: some View {
        switch suggestion {
        case .navigate(let url, let title):
            if title != nil {
                URLFavicon(url: url)
            } else {
                Image(systemName: "globe")
            }
        case .search: Image(systemName: "magnifyingglass")
        case .switchTo(let tab): FaviconView(tab: tab, size: 16)
        }
    }

    private var title: String {
        switch suggestion {
        case .navigate(let url, let title): title.flatMap { $0.isEmpty ? nil : $0 } ?? url.omniboxText
        case .search(let query, _): query
        case .switchTo(let tab): tab.displayTitle
        }
    }

    private var detail: String? {
        switch suggestion {
        case .navigate(let url, let title): title.flatMap { $0.isEmpty ? nil : url.omniboxText }
        case .search: browser.preferences.searchEngine.searchLabel
        case .switchTo(let tab): tab.url.displayHost
        }
    }

    private var hint: String? {
        switch suggestion {
        case .navigate: "Open"
        case .search: "Search"
        case .switchTo: "Switch to Tab"
        }
    }
}

/// A favicon for a URL that may not be open in any tab, e.g. in history or suggestions.
struct URLFavicon: View {
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
