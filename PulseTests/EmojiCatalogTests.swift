import Testing
@testable import Pulse

struct EmojiCatalogTests {
    private let catalog = EmojiCatalog.standard

    @Test func loadsEveryGroupWithoutSkinToneVariants() {
        #expect(catalog.groups.map(\.name) == [
            "Smileys & Emotion", "People & Body", "Animals & Nature", "Food & Drink",
            "Travel & Places", "Activities", "Objects", "Symbols", "Flags",
        ])
        let all = catalog.groups.flatMap(\.emojis)
        #expect(all.first == EmojiCatalog.Emoji(character: "😀", name: "grinning face"))
        #expect(all.contains { $0.character == "👋" })
        #expect(!all.contains { $0.character == "👋🏽" })
    }

    @Test func searchMatchesTheStartOfWords() {
        let cats = catalog.search("cat").map(\.character)
        #expect(cats.contains("🐱"))
        // "identification card" contains "cat" only mid-word.
        #expect(!cats.contains("🪪"))
        #expect(catalog.search("Red HEART").map(\.character).contains("❤️"))
        #expect(catalog.search("   ").isEmpty)
        #expect(catalog.search("zzzz").isEmpty)
    }
}
