import Foundation
import WebKit

/// Chrome's "Clear browsing data" time ranges.
enum BrowsingDataRange: CaseIterable, Identifiable {
    case lastHour, last24Hours, last7Days, last4Weeks, allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .lastHour: "Last hour"
        case .last24Hours: "Last 24 hours"
        case .last7Days: "Last 7 days"
        case .last4Weeks: "Last 4 weeks"
        case .allTime: "All time"
        }
    }

    /// `nil` means everything.
    func startDate(from now: Date = .now) -> Date? {
        switch self {
        case .lastHour: now.addingTimeInterval(-3600)
        case .last24Hours: now.addingTimeInterval(-86_400)
        case .last7Days: now.addingTimeInterval(-7 * 86_400)
        case .last4Weeks: now.addingTimeInterval(-28 * 86_400)
        case .allTime: nil
        }
    }
}

struct BrowsingDataSelection {
    var history = true
    var cookies = true
    var cache = true
}

enum BrowsingDataCleaner {
    private static let cacheTypes: Set<String> = [
        WKWebsiteDataTypeDiskCache,
        WKWebsiteDataTypeMemoryCache,
        WKWebsiteDataTypeFetchCache,
        WKWebsiteDataTypeOfflineWebApplicationCache,
    ]

    static func clear(_ selection: BrowsingDataSelection, in range: BrowsingDataRange, history: HistoryStore?) async {
        let since = range.startDate()
        if selection.history {
            history?.deleteVisits(since: since)
        }
        var types: Set<String> = []
        if selection.cookies { types.formUnion(WKWebsiteDataStore.allWebsiteDataTypes().subtracting(cacheTypes)) }
        if selection.cache { types.formUnion(cacheTypes) }
        guard !types.isEmpty else { return }
        await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: since ?? .distantPast)
    }
}
