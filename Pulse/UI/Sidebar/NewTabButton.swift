import SwiftUI

struct NewTabButton: View {
    @Environment(Browser.self) private var browser
    @State private var isHovered = false

    var body: some View {
        Button { browser.showCommandBar(.newTab) } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text("New Tab")
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .opacity(0.7)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                    .fill(isHovered ? Theme.hoverFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("New Tab (⌘T)")
    }
}
