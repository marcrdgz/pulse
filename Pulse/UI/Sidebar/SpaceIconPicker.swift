import SwiftUI

/// An emoji grid for a space's icon, like Arc's: one click sets it. Apple's character palette
/// is slow to open and inserts into a text field, which turns picking an icon into editing text.
struct SpaceIconPicker: View {
    @Environment(Browser.self) private var browser
    let space: Space
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private let catalog = EmojiCatalog.standard
    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 2), count: 8)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let first = catalog.search(query).first { choose(first) }
                    }
                Button {
                    browser.setIcon(nil, for: space)
                    browser.endEditingIcon()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(SidebarIconButtonStyle())
                .disabled(space.icon == nil)
                .help("Remove Icon")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if query.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(catalog.groups) { group in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 4)
                                    grid(group.emojis)
                                }
                                .id(group.id)
                            }
                        }
                    } else {
                        let results = catalog.search(query)
                        if results.isEmpty {
                            Text("No Emoji Found")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            grid(results)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: 240)
                Divider()
                HStack(spacing: 0) {
                    ForEach(catalog.groups) { group in
                        Button {
                            query = ""
                            proxy.scrollTo(group.id, anchor: .top)
                        } label: {
                            Image(systemName: Self.symbol(for: group.name))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SidebarIconButtonStyle())
                        .help(group.name)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 290)
        .onAppear { isSearchFocused = true }
    }

    private func grid(_ emojis: [EmojiCatalog.Emoji]) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(emojis, id: \.self) { emoji in
                EmojiCell(emoji: emoji, isSelected: emoji.character == space.icon) { choose(emoji) }
            }
        }
    }

    private func choose(_ emoji: EmojiCatalog.Emoji) {
        browser.setIcon(emoji.character, for: space)
        browser.endEditingIcon()
    }

    private static func symbol(for group: String) -> String {
        switch group {
        case "Smileys & Emotion": "face.smiling"
        case "People & Body": "hand.raised"
        case "Animals & Nature": "pawprint"
        case "Food & Drink": "cup.and.saucer"
        case "Travel & Places": "car"
        case "Activities": "soccerball"
        case "Objects": "lightbulb"
        case "Symbols": "heart"
        case "Flags": "flag"
        default: "circle"
        }
    }
}

private struct EmojiCell: View {
    let emoji: EmojiCatalog.Emoji
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(emoji.character)
                .font(.system(size: 22))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isSelected ? 0.14 : isHovered ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(emoji.name)
        .accessibilityLabel(emoji.name)
    }
}
