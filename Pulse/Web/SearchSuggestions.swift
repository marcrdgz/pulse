import Foundation

/// Query suggestions from the search engine, like Chrome's address bar shows.
enum SearchSuggestions {
    /// What's typed must leave nothing behind: no cache on disk, and no cookie tying private
    /// windows' queries to the engine's profile of the user.
    private static let session = URLSession(configuration: .cookieless(cache: nil))

    static func fetch(for query: String, from engine: SearchEngine, limit: Int = 4) async -> [String] {
        guard let url = engine.suggestionsURL(for: query),
              let (data, _) = try? await session.data(from: url),
              // ["query", ["suggestion 1", "suggestion 2", …]]
              let response = try? JSONSerialization.jsonObject(with: data) as? [Any],
              response.count > 1,
              let suggestions = response[1] as? [String]
        else { return [] }
        return Array(suggestions.prefix(limit))
    }
}

extension URLSessionConfiguration {
    /// For what Pulse fetches itself, outside web views. Cookies there would live in a jar of
    /// their own, shared by private windows and out of reach of Clear Browsing Data.
    static func cookieless(cache: URLCache?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = cache
        return configuration
    }
}
