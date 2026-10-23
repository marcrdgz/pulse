import Foundation
import Observation
import OSLog
import WebKit

/// Blocks ads and trackers like a Safari content blocker: EasyList and EasyPrivacy are compiled
/// into WebKit rule lists that every page loads with, except on sites the user allowed.
@Observable
final class ContentBlocker {
    static let filterListURLs = [
        URL(string: "https://easylist.to/easylist/easylist.txt")!,
        URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
    ]
    /// The lists ask clients to refresh every four days.
    static let updateInterval: TimeInterval = 4 * 24 * 60 * 60

    private(set) var ruleLists: [WKContentRuleList] = []
    private(set) var lastUpdate: Date?

    @ObservationIgnored weak var browser: Browser?
    @ObservationIgnored private let store: WKContentRuleListStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    private enum Key {
        static let identifiers = "contentBlockerIdentifiers"
        static let lastUpdate = "contentBlockerLastUpdate"
    }

    /// Without a store nothing is downloaded or compiled, so tests stay offline.
    init(store: WKContentRuleListStore? = nil, defaults: UserDefaults? = nil, preferences: Preferences = Preferences()) {
        self.store = store
        self.defaults = defaults
        self.preferences = preferences
        lastUpdate = defaults?.object(forKey: Key.lastUpdate) as? Date
    }

    var isEnabled: Bool { preferences.blocksAdsAndTrackers }

    /// The lists a page loads with: none when blocking is off, globally or for its site.
    func rules(forPageAt url: URL) -> [WKContentRuleList] {
        isBlocking(on: url) ? ruleLists : []
    }

    func isBlocking(on url: URL) -> Bool {
        guard isEnabled, let host = url.displayHost else { return isEnabled }
        return !preferences.adsAllowedSites.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func setEnabled(_ isEnabled: Bool) {
        preferences.blocksAdsAndTrackers = isEnabled
        browser?.contentRulesDidChange()
    }

    /// Allowing a site also allows its subdomains.
    func setBlocking(_ isBlocking: Bool, onSite site: String) {
        var sites = Set(preferences.adsAllowedSites)
        if isBlocking { sites.remove(site) } else { sites.insert(site) }
        preferences.adsAllowedSites = sites.sorted()
        browser?.contentRulesDidChange()
    }

    /// Loads the lists compiled on a previous launch, then keeps them fresh while Pulse runs.
    func start() {
        guard let store, updateTask == nil else { return }
        updateTask = Task { [weak self] in
            await self?.loadCompiledLists(from: store)
            while !Task.isCancelled {
                guard let self else { return }
                if lastUpdate.map({ Date.now.timeIntervalSince($0) > Self.updateInterval }) ?? true {
                    await update(store)
                }
                // Hourly checks retry soon after a failed download without hammering the servers.
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    private func loadCompiledLists(from store: WKContentRuleListStore) async {
        let identifiers = defaults?.stringArray(forKey: Key.identifiers) ?? []
        var lists: [WKContentRuleList] = []
        for identifier in identifiers {
            if let list = try? await store.contentRuleList(forIdentifier: identifier) { lists.append(list) }
        }
        guard !lists.isEmpty, lists.count == identifiers.count else {
            lastUpdate = nil
            return
        }
        install(lists)
    }

    private func update(_ store: WKContentRuleListStore) async {
        do {
            var filterLists: [String] = []
            for url in Self.filterListURLs {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                filterLists.append(String(decoding: data, as: UTF8.self))
            }
            // Converting ~140k filters takes seconds; keep it off the main thread.
            let encodedLists = try await Task.detached(priority: .utility) {
                try FilterList.encodedRuleLists(from: filterLists)
            }.value

            // A new generation per update, so pages keep the old lists until the new ones are in.
            let generation = Int(Date.now.timeIntervalSince1970)
            var lists: [WKContentRuleList] = []
            for (index, encoded) in encodedLists.enumerated() {
                do {
                    let identifier = "ads-and-trackers-\(generation)-\(index)"
                    if let list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encoded) {
                        lists.append(list)
                    }
                } catch {
                    Logger.contentBlocker.error("Failed to compile rule list \(index): \(error.localizedDescription)")
                }
            }
            guard !lists.isEmpty else { return }

            install(lists)
            lastUpdate = .now
            defaults?.set(lists.compactMap(\.identifier), forKey: Key.identifiers)
            defaults?.set(lastUpdate, forKey: Key.lastUpdate)
            for identifier in await store.availableIdentifiers() ?? [] where !lists.contains(where: { $0.identifier == identifier }) {
                try? await store.removeContentRuleList(forIdentifier: identifier)
            }
        } catch {
            Logger.contentBlocker.error("Failed to update filter lists: \(error.localizedDescription)")
        }
    }

    private func install(_ lists: [WKContentRuleList]) {
        ruleLists = lists
        browser?.contentRulesDidChange()
    }
}

extension Logger {
    static let contentBlocker = Logger(subsystem: "dev.doblefilo.pulse", category: "ContentBlocker")
}
