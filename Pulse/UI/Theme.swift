import AppKit
import SwiftUI

enum Theme {
    static let defaultSidebarWidth: Double = 240
    static let sidebarWidthRange: ClosedRange<Double> = 200...420
    static let collapsedSidebarWidth: CGFloat = 52
    static let contentInset: CGFloat = 8
    static let contentCornerRadius: CGFloat = 10
    static let rowCornerRadius: CGFloat = 8
    /// Arc's bottom-bar targets are larger than the toolbar's.
    static let bottomBarButtonSize: CGFloat = 30

    static func sidebarGradient(_ theme: SpaceTheme) -> LinearGradient {
        let palette = palette(theme)
        return LinearGradient(
            colors: [
                .dynamic(light: NSColor(hex: palette.light.0), dark: NSColor(hex: palette.dark.0)),
                .dynamic(light: NSColor(hex: palette.light.1), dark: NSColor(hex: palette.dark.1)),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The saturated color identifying a space in the switcher and its header.
    static func swatch(_ theme: SpaceTheme) -> Color {
        Color(nsColor: NSColor(hex: palette(theme).swatch))
    }

    private static func palette(_ theme: SpaceTheme) -> (light: (UInt32, UInt32), dark: (UInt32, UInt32), swatch: UInt32) {
        switch theme {
        case .purple: ((0xB9A7F2, 0x9DBAF2), (0x3A2E66, 0x1F3358), 0x8B6CF0)
        case .blue: ((0xA7C7F2, 0x9DE0F2), (0x1E3A66, 0x1A4A5A), 0x4A90E8)
        case .green: ((0xA7E0C4, 0xC8E8A7), (0x1E4A3A, 0x2A4A22), 0x3CB37A)
        case .orange: ((0xF5C8A0, 0xF2A7A7), (0x5A3A1E, 0x5A2626), 0xF0903C)
        case .pink: ((0xF2A7D3, 0xC9A7F2), (0x5A1E44, 0x3E2A66), 0xE85AA8)
        case .graphite: ((0xCFCFD6, 0xB5B8C2), (0x2E2E34, 0x24262C), 0x8A8D96)
        }
    }
    /// Settings panes take their tiles in order along the halo's gradient, so the list reads as one sweep of the mark.
    static func settingsTile(_ pane: SettingsPane) -> Color {
        let hex: UInt32 = switch pane {
        case .general: 0xF5862A
        case .search: 0xE8506A
        case .downloads: 0xD2337E
        case .privacy: 0x7B4DFF
        case .extensions: 0x4B3BB8
        }
        return Color(nsColor: NSColor(hex: hex))
    }

    static let sidebarText = Color.dynamic(light: NSColor(hex: 0x1F1B33), dark: NSColor(hex: 0xF2F0FA))
    static let activeTabFill = Color.dynamic(light: .white.withAlphaComponent(0.85), dark: .white.withAlphaComponent(0.16))
    static let hoverFill = Color.dynamic(light: .white.withAlphaComponent(0.3), dark: .white.withAlphaComponent(0.07))
    /// Arc darkens behind a hovered icon instead of lightening, which reads on pale themes too.
    static let iconHoverFill = Color.dynamic(light: .black.withAlphaComponent(0.08), dark: .white.withAlphaComponent(0.12))
    static let pillFill = Color.dynamic(light: .white.withAlphaComponent(0.4), dark: .white.withAlphaComponent(0.09))
}

/// Borderless icon button with Arc's subtle hover highlight.
struct SidebarIconButtonStyle: ButtonStyle {
    /// The hover square's side; the bottom bar uses Arc's larger targets.
    var size: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        SidebarIconButton(configuration: configuration, size: size)
    }

    private struct SidebarIconButton: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(minWidth: size, minHeight: size)
                .background(
                    // Fades rather than snapping.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.iconHoverFill)
                        .opacity(isHovered && isEnabled ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: isHovered)
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
                .onHover { isHovered = $0 }
        }
    }
}

/// The palette of the Halo mark, as the site uses it (`site/src/styles/global.css`). The ring's
/// gradient belongs to the mark; pages use the flare and accent as single colors.
enum Brand {
    static let ring: [Color] = [
        .dynamic(light: NSColor(hex: 0xFF9A3D), dark: NSColor(hex: 0xFFC27A)),
        .dynamic(light: NSColor(hex: 0xE0307A), dark: NSColor(hex: 0xFF5A9A)),
        .dynamic(light: NSColor(hex: 0x7B4DFF), dark: NSColor(hex: 0xA98BFF)),
        .dynamic(light: NSColor(hex: 0x2A1B6B), dark: NSColor(hex: 0x8B7BFF)),
    ]
    static let flare = Color.dynamic(light: NSColor(hex: 0xFF8A4C), dark: NSColor(hex: 0xFFB547))
    static let glow = Color.dynamic(light: NSColor(hex: 0xFFB547), dark: NSColor(hex: 0xFFC27A))
    static let accent = Color.dynamic(light: NSColor(hex: 0x7B4DFF), dark: NSColor(hex: 0xA98BFF))
    static let paper = Color.dynamic(light: NSColor(hex: 0xF4F2F8), dark: NSColor(hex: 0x12101C))
    static let card = Color.dynamic(light: .white, dark: NSColor(hex: 0x1B1926))
    static let ink = Color.dynamic(light: NSColor(hex: 0x15131D), dark: NSColor(hex: 0xF4F3FA))
    static let dim = Color.dynamic(light: NSColor(hex: 0x6B6787), dark: NSColor(hex: 0xA19DB8))
    static let line = Color.dynamic(light: NSColor(hex: 0xE3E0EE), dark: NSColor(hex: 0x2D2A3C))
}

extension AnyTransition {
    /// Slides in from `edge` while fading, or only fades when the user asked to reduce motion.
    static func slide(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
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
