import AppKit
import SwiftUI

enum Theme {
    static let defaultSidebarWidth: Double = 240
    static let sidebarWidthRange: ClosedRange<Double> = 200...420
    static let contentInset: CGFloat = 8
    static let contentCornerRadius: CGFloat = 10
    static let rowCornerRadius: CGFloat = 8

    static let sidebarGradient = LinearGradient(
        colors: [
            .dynamic(light: NSColor(hex: 0xB9A7F2), dark: NSColor(hex: 0x3A2E66)),
            .dynamic(light: NSColor(hex: 0x9DBAF2), dark: NSColor(hex: 0x1F3358)),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let sidebarText = Color.dynamic(light: NSColor(hex: 0x1F1B33), dark: NSColor(hex: 0xF2F0FA))
    static let activeTabFill = Color.dynamic(light: .white.withAlphaComponent(0.85), dark: .white.withAlphaComponent(0.16))
    static let hoverFill = Color.dynamic(light: .white.withAlphaComponent(0.3), dark: .white.withAlphaComponent(0.07))
    static let pillFill = Color.dynamic(light: .white.withAlphaComponent(0.4), dark: .white.withAlphaComponent(0.09))
}

/// Borderless icon button with Arc's subtle hover highlight.
struct SidebarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarIconButton(configuration: configuration)
    }

    private struct SidebarIconButton: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(minWidth: 26, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered && isEnabled ? Theme.hoverFill : .clear)
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
                .onHover { isHovered = $0 }
        }
    }
}

private extension Color {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
