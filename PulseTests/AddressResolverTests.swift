import Foundation
import Testing
@testable import Pulse

struct AddressResolverTests {
    @Test(arguments: [
        ("https://swift.org/blog", "https://swift.org/blog"),
        ("  HTTP://Example.com  ", "HTTP://Example.com"),
        ("example.com", "https://example.com"),
        ("news.ycombinator.com/item?id=1", "https://news.ycombinator.com/item?id=1"),
        ("localhost:3000/admin", "http://localhost:3000/admin"),
        ("192.168.1.1", "http://192.168.1.1"),
        ("about:blank", "about:blank"),
    ])
    func resolvesAddresses(input: String, expected: String) {
        #expect(AddressResolver.destination(for: input) == .url(URL(string: expected)!))
    }

    @Test(arguments: ["swift concurrency", "pulse", "example.com is down", "v1.2", "https://"])
    func fallsBackToSearch(input: String) throws {
        let destination = try #require(AddressResolver.destination(for: input))
        #expect(destination == .search(query: input, url: try #require(SearchEngine.google.searchURL(for: input))))
    }

    @Test func encodesSearchQuery() {
        #expect(
            SearchEngine.google.searchURL(for: "a&b c")?.absoluteString
                == "https://www.google.com/search?q=a%26b%20c"
        )
    }

    @Test func ignoresBlankInput() {
        #expect(AddressResolver.destination(for: "   ") == nil)
    }
}

struct SearchEngineTests {
    @Test func searchesWithTheChosenEngine() {
        #expect(AddressResolver.destination(for: "swift ui", searchEngine: .duckDuckGo)?.url.absoluteString
            == "https://duckduckgo.com/?q=swift%20ui")
        #expect(SearchEngine.kagi.searchURL(for: "a")?.absoluteString == "https://kagi.com/search?q=a")
    }

    @Test func suggestionURLsKeepTheirFixedParameters() {
        #expect(SearchEngine.google.suggestionsURL(for: "a")?.absoluteString
            == "https://suggestqueries.google.com/complete/search?client=firefox&q=a")
        #expect(SearchEngine.bing.suggestionsURL(for: "a")?.absoluteString == "https://api.bing.com/osjson.aspx?query=a")
    }

    @Test func preferencesPersistInTheirDefaults() {
        let defaults = UserDefaults(suiteName: "PulseTests-\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        preferences.searchEngine = .kagi
        preferences.showsSearchSuggestions = false

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.searchEngine == .kagi)
        #expect(!reloaded.showsSearchSuggestions)
        #expect(Preferences().startupBehavior == .continueWhereYouLeftOff)
    }
}
