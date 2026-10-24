import Foundation
import Observation

enum SearchEngine: String, CaseIterable, Identifiable {
    case google, duckDuckGo, bing, brave, ecosia, kagi

    var id: Self { self }

    var name: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .brave: "Brave Search"
        case .ecosia: "Ecosia"
        case .kagi: "Kagi"
        }
    }

    /// How Chrome labels search suggestions: "swift – Google Search".
    var searchLabel: String {
        name.hasSuffix("Search") ? name : "\(name) Search"
    }

    func searchURL(for query: String) -> URL? {
        url(searchBase, query: query)
    }

    /// OpenSearch suggestion endpoints: they answer `["query", ["suggestion", …]]`.
    func suggestionsURL(for query: String) -> URL? {
        url(suggestionsBase, query: query)
    }

    private var searchBase: (String, String) {
        switch self {
        case .google: ("https://www.google.com/search", "q")
        case .duckDuckGo: ("https://duckduckgo.com/", "q")
        case .bing: ("https://www.bing.com/search", "q")
        case .brave: ("https://search.brave.com/search", "q")
        case .ecosia: ("https://www.ecosia.org/search", "q")
        case .kagi: ("https://kagi.com/search", "q")
        }
    }

    private var suggestionsBase: (String, String) {
        switch self {
        case .google: ("https://suggestqueries.google.com/complete/search?client=firefox", "q")
        case .duckDuckGo: ("https://duckduckgo.com/ac/?type=list", "q")
        case .bing: ("https://api.bing.com/osjson.aspx", "query")
        case .brave: ("https://search.brave.com/api/suggest", "q")
        case .ecosia: ("https://ac.ecosia.org/autocomplete?type=list", "q")
        case .kagi: ("https://kagi.com/api/autosuggest", "q")
        }
    }

    private func url(_ base: (String, String), query: String) -> URL? {
        var components = URLComponents(string: base.0)
        let fixedItems = components?.queryItems ?? []
        components?.queryItems = fixedItems + [URLQueryItem(name: base.1, value: query)]
        return components?.url
    }
}

enum StartupBehavior: String, CaseIterable, Identifiable {
    /// Chrome's "Continue where you left off".
    case continueWhereYouLeftOff
    /// Favorites and pinned tabs come back, Today starts empty.
    case clearToday

    var id: Self { self }

    var title: String {
        switch self {
        case .continueWhereYouLeftOff: "Continue where you left off"
        case .clearToday: "Start with an empty Today"
        }
    }
}

/// Minutes off screen before a tab sleeps.
enum TabSleepDelay: Int, CaseIterable, Identifiable {
    case never = 0
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120

    var id: Self { self }

    var duration: TimeInterval? { self == .never ? nil : TimeInterval(rawValue * 60) }

    var title: String {
        switch self {
        case .never: "Never"
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        }
    }
}

/// User settings, stored in `UserDefaults` when one is given (in memory otherwise, for tests).
@Observable
final class Preferences {
    var searchEngine: SearchEngine { didSet { save(searchEngine.rawValue, Key.searchEngine) } }
    /// Sends what you type in the address bar to the search engine, like Chrome does by default.
    var showsSearchSuggestions: Bool { didSet { save(showsSearchSuggestions, Key.searchSuggestions) } }
    var startupBehavior: StartupBehavior { didSet { save(startupBehavior.rawValue, Key.startup) } }
    var asksWhereToSaveDownloads: Bool { didSet { save(asksWhereToSaveDownloads, Key.askDownloadLocation) } }
    var hasCompletedOnboarding: Bool { didSet { save(hasCompletedOnboarding, Key.onboarding) } }
    var blocksAdsAndTrackers: Bool { didSet { save(blocksAdsAndTrackers, Key.blocksAds) } }
    /// Sites (without `www.`) where ads and trackers load, sorted.
    var adsAllowedSites: [String] { didSet { save(adsAllowedSites, Key.adsAllowedSites) } }
    /// How long a tab stays off screen before it sleeps.
    var tabSleepDelay: TabSleepDelay { didSet { save(tabSleepDelay.rawValue, Key.tabSleepDelay) } }
    /// Links from a pinned tab or favorite to another site open in Peek, like Arc, so the pinned page stays put.
    var opensPinnedLinksInPeek: Bool { didSet { save(opensPinnedLinksInPeek, Key.pinnedLinksInPeek) } }
    /// The version whose What's New was last offered, so each update announces itself once.
    var lastSeenVersion: String? { didSet { if let lastSeenVersion { save(lastSeenVersion, Key.lastSeenVersion) } } }

    @ObservationIgnored private let defaults: UserDefaults?

    private enum Key {
        static let searchEngine = "searchEngine"
        static let searchSuggestions = "showsSearchSuggestions"
        static let startup = "startupBehavior"
        static let askDownloadLocation = "asksWhereToSaveDownloads"
        static let onboarding = "hasCompletedOnboarding"
        static let blocksAds = "blocksAdsAndTrackers"
        static let adsAllowedSites = "adsAllowedSites"
        static let tabSleepDelay = "tabSleepDelayMinutes"
        static let pinnedLinksInPeek = "opensPinnedLinksInPeek"
        static let lastSeenVersion = "lastSeenVersion"
    }

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        searchEngine = defaults?.string(forKey: Key.searchEngine).flatMap(SearchEngine.init) ?? .google
        showsSearchSuggestions = defaults?.object(forKey: Key.searchSuggestions) as? Bool ?? true
        startupBehavior = defaults?.string(forKey: Key.startup).flatMap(StartupBehavior.init) ?? .continueWhereYouLeftOff
        asksWhereToSaveDownloads = defaults?.bool(forKey: Key.askDownloadLocation) ?? false
        hasCompletedOnboarding = defaults?.bool(forKey: Key.onboarding) ?? false
        blocksAdsAndTrackers = defaults?.object(forKey: Key.blocksAds) as? Bool ?? true
        adsAllowedSites = defaults?.stringArray(forKey: Key.adsAllowedSites) ?? []
        tabSleepDelay = (defaults?.object(forKey: Key.tabSleepDelay) as? Int).flatMap(TabSleepDelay.init) ?? .oneHour
        opensPinnedLinksInPeek = defaults?.object(forKey: Key.pinnedLinksInPeek) as? Bool ?? true
        lastSeenVersion = defaults?.string(forKey: Key.lastSeenVersion)
    }

    private func save(_ value: Any, _ key: String) {
        defaults?.set(value, forKey: key)
    }
}
