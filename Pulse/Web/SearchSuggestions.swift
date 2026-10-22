import Foundation

/// Query suggestions from the search engine, like Chrome's address bar shows.
enum SearchSuggestions {
    static func fetch(for query: String, limit: Int = 4) async -> [String] {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "q", value: query),
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              // ["query", ["suggestion 1", "suggestion 2", …]]
              let response = try? JSONSerialization.jsonObject(with: data) as? [Any],
              response.count > 1,
              let suggestions = response[1] as? [String]
        else { return [] }
        return Array(suggestions.prefix(limit))
    }
}
