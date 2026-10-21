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
        #expect(destination == .search(query: input, url: try #require(AddressResolver.searchURL(for: input))))
    }

    @Test func encodesSearchQuery() {
        #expect(
            AddressResolver.searchURL(for: "a&b c")?.absoluteString
                == "https://www.google.com/search?q=a%26b%20c"
        )
    }

    @Test func ignoresBlankInput() {
        #expect(AddressResolver.destination(for: "   ") == nil)
    }
}
