import Foundation

/// Turns what the user typed in the command bar into the page to load.
enum AddressResolver {
    enum Destination: Equatable {
        case url(URL)
        case search(query: String, url: URL)

        var url: URL {
            switch self {
            case .url(let url), .search(_, let url): url
            }
        }
    }

    private static let explicitSchemes: Set<String> = ["http", "https", "file", "about", "data"]

    static func destination(for input: String) -> Destination? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = explicitURL(text) ?? implicitURL(text) {
            return .url(url)
        }
        return searchURL(for: text).map { .search(query: text, url: $0) }
    }

    static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    private static func explicitURL(_ text: String) -> URL? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              explicitSchemes.contains(scheme)
        else { return nil }
        if scheme.hasPrefix("http"), components.host?.isEmpty ?? true { return nil }
        return components.url
    }

    /// Addresses typed without a scheme, e.g. `example.com/path` or `localhost:3000`.
    private static func implicitURL(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace),
              let host = URLComponents(string: "http://\(text)")?.host?.lowercased()
        else { return nil }

        if host == "localhost" || isIPv4(host) {
            return URL(string: "http://\(text)")
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1,
              labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }),
              let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter)
        else { return nil }
        return URL(string: "https://\(text)")
    }

    private static func isIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { UInt8($0) != nil }
    }
}
