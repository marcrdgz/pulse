import Foundation

/// The emoji offered as space icons, grouped as Unicode groups them.
/// Read from `Emoji.txt`, which `scripts/generate-emoji-list.py` writes.
struct EmojiCatalog {
    struct Emoji: Hashable {
        let character: String
        let name: String
    }

    struct Group: Identifiable {
        let name: String
        let emojis: [Emoji]

        var id: String { name }
    }

    let groups: [Group]

    static let standard: EmojiCatalog = {
        guard let url = Bundle.main.url(forResource: "Emoji", withExtension: "txt"),
              let list = try? String(contentsOf: url, encoding: .utf8)
        else { return EmojiCatalog(groups: []) }
        return EmojiCatalog(list: list)
    }()

    init(groups: [Group]) {
        self.groups = groups
    }

    /// `list` has a "## Group" line before each group's "emoji<TAB>name" lines; other "#" lines are comments.
    init(list: String) {
        var groups: [Group] = []
        var name: String?
        var emojis: [Emoji] = []
        for line in list.split(separator: "\n") {
            if line.hasPrefix("## ") {
                if let name { groups.append(Group(name: name, emojis: emojis)) }
                name = String(line.dropFirst(3))
                emojis = []
            } else if !line.hasPrefix("#"), let tab = line.firstIndex(of: "\t") {
                emojis.append(Emoji(character: String(line[..<tab]), name: String(line[line.index(after: tab)...])))
            }
        }
        if let name { groups.append(Group(name: name, emojis: emojis)) }
        self.groups = groups
    }

    /// Every word of `query` must start a word of the name, so "cat" finds "cat face" but not "education".
    func search(_ query: String) -> [Emoji] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return [] }
        return groups.flatMap(\.emojis).filter { emoji in
            let words = emoji.name.lowercased().split { !$0.isLetter && !$0.isNumber }
            return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
        }
    }
}
