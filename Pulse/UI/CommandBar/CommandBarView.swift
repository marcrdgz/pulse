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
        let accent = Theme.swatch(browser.activeSpace.theme)
        VStack(spacing: 0) {
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
            .padding(.horizontal, 20)
            .frame(height: 60)

            if !suggestions.isEmpty {
                Rectangle()
                    .fill(.primary.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                VStack(spacing: 2) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            isSelected: index == selectedIndex,
                            accent: accent,
                            remove: removeAction(for: suggestion)
                        )
                        .onTapGesture { perform(suggestion) }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 680)
        // Arc tints the bar with the active space's color.
        .background(
            LinearGradient(colors: [accent.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)
        )
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        )
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.28), radius: 40, y: 20)
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
    /// The active space's color, which fills the highlighted row as in Arc.
    let accent: Color
    let remove: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? .white.opacity(0.25) : Color.primary.opacity(0.06))
                )
            HStack(spacing: 0) {
                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let detail {
                    Text(" — \(detail)")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
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
            } else if let hint, isSelected || isTabSwitch {
                HStack(spacing: 6) {
                    Text(hint)
                    if isSelected {
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 18)
                            .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? accent : isHovered ? Color.primary.opacity(0.05) : .clear)
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
