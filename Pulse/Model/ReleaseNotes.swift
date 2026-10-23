import Foundation

/// What a release changed, as `pulse://whats-new` shows it. The `/release` skill writes
/// `Resources/ReleaseNotes.json`, newest release first.
struct ReleaseNotes: Decodable, Identifiable {
    struct Highlight: Decodable, Identifiable {
        let title: String
        let body: String
        /// An SF Symbol, drawn when there's no scene.
        let symbol: String
        /// The menu shortcut that tries it, written like the menus show it.
        let shortcut: String?
        let scene: WhatsNewScene?

        var id: String { title }
    }

    let version: String
    let date: Date
    let summary: String
    let highlights: [Highlight]
    let improvements: [String]
    let fixes: [String]

    var id: String { version }

    static let bundled: [ReleaseNotes] = {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"),
              let json = try? Data(contentsOf: url)
        else { return [] }
        // A test decodes the bundled file, so a broken one never ships.
        return (try? decode(json)) ?? []
    }()

    static func decode(_ json: Data) throws -> [ReleaseNotes] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(formatter)
        return try decoder.decode([ReleaseNotes].self, from: json)
    }
}

/// The animated drawings a highlight can show; `WhatsNewScenes.swift` draws each one.
enum WhatsNewScene: String, Decodable {
    case splitView
    case extensions
    case adBlocking
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
