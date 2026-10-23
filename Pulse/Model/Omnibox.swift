import Foundation

enum OmniboxSuggestion: Identifiable {
    /// A typed address or a page from history.
    case navigate(URL, title: String?)
    case search(query: String, url: URL)
    case switchTo(Tab)

    var id: String {
        switch self {
        case .navigate(let url, _): "url:\(url.absoluteString)"
        case .search(let query, _): "search:\(query)"
        case .switchTo(let tab): "tab:\(tab.id)"
        }
    }

    /// What the address field shows while the suggestion is highlighted with the arrow keys.
    var fillText: String {
        switch self {
        case .navigate(let url, _): url.absoluteString
        case .search(let query, _): query
        case .switchTo(let tab): tab.url.absoluteString
        }
    }
}

struct OmniboxResult {
    var suggestions: [OmniboxSuggestion]
    /// The full text to show, starting with exactly what was typed; the rest is selected.
    var inlineCompletion: String?
}

/// Chrome's address bar behavior: inline-complete addresses you go to often, then list what you
/// typed, history ranked by frequency and recency, open tabs and search suggestions.
enum Omnibox {
    static let maxSuggestions = 8

    static func result(
        for input: String,
        history: [HistoryEntry],
        openTabs: [Tab],
        searchSuggestions: [String],
        allowsInlineCompletion: Bool,
        searchEngine: SearchEngine = .google,
        now: Date = .now
    ) -> OmniboxResult {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            return OmniboxResult(suggestions: openTabs.prefix(6).map(OmniboxSuggestion.switchTo), inlineCompletion: nil)
        }
        let needle = text.lowercased()
        let ranked = history
            .map { (entry: $0, score: score($0, for: needle, now: now)) }
            .sorted { $0.score > $1.score }
            .map(\.entry)

        var suggestions: [OmniboxSuggestion] = []
        var inlineCompletion: String?
        if allowsInlineCompletion, !needle.contains(" "),
           let best = ranked.first(where: { isFrequent($0) && $0.url.omniboxText.hasPrefix(needle) }) {
            let (fill, url) = completion(of: best, for: needle)
            inlineCompletion = text + fill.dropFirst(needle.count)
            suggestions.append(.navigate(url, title: url == best.url ? best.title : nil))
        }
        if let destination = AddressResolver.destination(for: text, searchEngine: searchEngine) {
            switch destination {
            case .url(let url): suggestions.append(.navigate(url, title: nil))
            case .search(let query, let url): suggestions.append(.search(query: query, url: url))
            }
        }

        for entry in ranked.prefix(10) {
            if let tab = openTabs.first(where: { $0.url == entry.url }) {
                suggestions.append(.switchTo(tab))
            } else {
                suggestions.append(.navigate(entry.url, title: entry.title))
            }
        }
        let matchingTabs = openTabs.filter {
            $0.displayTitle.lowercased().contains(needle) || $0.url.absoluteString.lowercased().contains(needle)
        }
        suggestions += matchingTabs.prefix(3).map(OmniboxSuggestion.switchTo)
        suggestions += searchSuggestions
            .filter { $0.lowercased() != needle }
            .compactMap { query in searchEngine.searchURL(for: query).map { .search(query: query, url: $0) } }

        return OmniboxResult(suggestions: deduplicated(suggestions), inlineCompletion: inlineCompletion)
    }

    /// Typed addresses dominate, then visit count, all fading with time; matches at the start of
    /// the address beat matches in the middle or in the title.
    static func score(_ entry: HistoryEntry, for needle: String, now: Date) -> Double {
        let frequency = Double(min(entry.typedCount, 20)) * 20 + Double(min(entry.visitCount, 30)) * 5
        // Chrome-like age buckets: what you used this week clearly beats what you used a lot months ago.
        let days = now.timeIntervalSince(entry.lastVisit) / 86_400
        let recency = days < 4 ? 1.0 : days < 14 ? 0.5 : days < 31 ? 0.25 : days < 90 ? 0.1 : 0.05
        let firstTerm = needle.split(separator: " ").first.map(String.init) ?? needle
        let match: Double
        if entry.url.omniboxText.hasPrefix(firstTerm) {
            match = 60
        } else if entry.url.host()?.lowercased().contains(firstTerm) == true {
            match = 25
        } else if entry.title.lowercased().split(separator: " ").contains(where: { $0.hasPrefix(firstTerm) }) {
            match = 15
        } else {
            match = 0
        }
        return frequency * recency + match
    }

    /// Only addresses typed before or visited repeatedly are completed inline, as in Chrome.
    private static func isFrequent(_ entry: HistoryEntry) -> Bool {
        entry.typedCount > 0 || entry.visitCount >= 2
    }

    /// Completes the host while typing it ("git" → "github.com"), the whole address after a "/".
    private static func completion(of entry: HistoryEntry, for needle: String) -> (fill: String, url: URL) {
        guard !needle.contains("/"), let host = entry.url.host(), let scheme = entry.url.scheme,
              let hostURL = URL(string: "\(scheme)://\(host)/")
        else { return (entry.url.omniboxText, entry.url) }
        return (hostURL.omniboxText.trimmingCharacters(in: CharacterSet(charactersIn: "/")), hostURL)
    }

    private static func deduplicated(_ suggestions: [OmniboxSuggestion]) -> [OmniboxSuggestion] {
        var seenIDs: Set<String> = []
        var seenURLs: Set<String> = []
        var result: [OmniboxSuggestion] = []
        for suggestion in suggestions {
            let url: String? = switch suggestion {
            case .navigate(let url, _): url.omniboxText
            case .switchTo(let tab): tab.url.omniboxText
            case .search: nil
            }
            guard seenIDs.insert(suggestion.id).inserted else { continue }
            if let url, !seenURLs.insert(url).inserted { continue }
            result.append(suggestion)
            if result.count == maxSuggestions { break }
        }
        return result
    }
}

extension URL {
    /// The address as the omnibox matches it: lowercase, without scheme, `www.` or trailing slash.
    var omniboxText: String {
        var text = absoluteString.lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
