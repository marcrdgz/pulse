import SwiftUI

/// Small looping drawings of Pulse for release highlights, in the spirit of the landing page's
/// screen mock: no recordings to keep current, and they follow the appearance. With Reduce
/// Motion each one holds on its last frame.
struct WhatsNewSceneView: View {
    let scene: WhatsNewScene

    var body: some View {
        switch scene {
        case .splitView: SplitViewScene()
        case .extensions: ExtensionsScene()
        case .adBlocking: AdBlockingScene()
        }
    }
}

// MARK: Scenes

/// A tab lifts out of the sidebar and lands on the page's right half, which becomes a split.
private struct SplitViewScene: View {
    private enum Phase: CaseIterable { case resting, dragging, split }

    var body: some View {
        Looping(Phase.allCases) { phase in
            switch phase {
            case .resting: .easeInOut(duration: 0.4).delay(1.8)
            case .dragging: .spring(duration: 0.8).delay(0.8)
            case .split: .spring(duration: 0.5).delay(0.3)
            }
        } content: { phase in
            MiniWindow(activeRow: 0, dimmedRow: phase == .dragging ? 2 : nil) {
                HStack(spacing: 4) {
                    PageLines()
                    if phase == .split {
                        Rectangle().fill(.separator).frame(width: 1)
                        PageLines(widths: [0.7, 1, 0.85, 0.5])
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .trailing) {
                    if phase == .dragging {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Brand.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .background(Brand.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .frame(width: 148)
                            .padding(6)
                            .transition(.opacity)
                    }
                }
            } addressAccessory: {
                EmptyView()
            }
            .overlay(alignment: .topLeading) {
                MiniTabRow(isActive: true)
                    .frame(width: 102)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    .scaleEffect(phase == .dragging ? 1.06 : 1)
                    .offset(phase == .dragging ? CGSize(width: 300, height: 96) : CGSize(width: 8, height: 92))
                    .opacity(phase == .dragging ? 1 : 0)
            }
        }
    }
}

/// "Add to Pulse" on a store page installs the extension, whose icon pops into the sidebar.
private struct ExtensionsScene: View {
    private enum Phase: CaseIterable { case browsing, pressing, installed }

    var body: some View {
        Looping(Phase.allCases) { phase in
            switch phase {
            case .browsing: .easeOut(duration: 0.3).delay(2)
            case .pressing: .easeIn(duration: 0.12).delay(1.2)
            case .installed: .spring(duration: 0.5, bounce: 0.45).delay(0.1)
            }
        } content: { phase in
            MiniWindow {
                HStack(alignment: .top, spacing: 10) {
                    ExtensionIcon(size: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().frame(width: 90, height: 7).opacity(0.35)
                        Capsule().frame(width: 130, height: 5).opacity(0.18)
                        Capsule().frame(width: 110, height: 5).opacity(0.18)
                    }
                    Spacer()
                    Text(phase == .installed ? "Added" : "Add to Pulse")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            phase == .installed ? Color.gray : Brand.accent,
                            in: Capsule()
                        )
                        .scaleEffect(phase == .pressing ? 0.88 : 1)
                }
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .top)
            } addressAccessory: {
                HStack(spacing: 4) {
                    if phase == .installed {
                        ExtensionIcon(size: 10)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 8))
                }
            }
        }
    }
}

/// The ads on a page fold away and the shield in the address bar counts them.
private struct AdBlockingScene: View {
    private enum Phase: CaseIterable { case loaded, blocked }

    var body: some View {
        Looping(Phase.allCases) { phase in
            switch phase {
            case .loaded: .easeInOut(duration: 0.4).delay(2)
            case .blocked: .spring(duration: 0.6).delay(1.2)
            }
        } content: { phase in
            MiniWindow {
                VStack(alignment: .leading, spacing: 7) {
                    PageLines(widths: [1, 0.8])
                    ad(isBlocked: phase == .blocked)
                    PageLines(widths: [0.95, 1, 0.6], hasHeadline: false)
                    ad(isBlocked: phase == .blocked)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } addressAccessory: {
                HStack(spacing: 2) {
                    Image(systemName: phase == .blocked ? "checkmark.shield.fill" : "shield")
                        .contentTransition(.symbolEffect(.replace))
                    if phase == .blocked {
                        Text("2").fontWeight(.bold)
                    }
                }
                .font(.system(size: 8))
                .foregroundStyle(phase == .blocked ? Brand.accent : Theme.sidebarText.opacity(0.5))
            }
        }
    }

    private func ad(isBlocked: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.yellow.opacity(0.3))
            .overlay {
                Text("AD")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.4))
            }
            .frame(height: isBlocked ? 0 : 30)
            .opacity(isBlocked ? 0 : 1)
            .padding(.horizontal, 14)
    }
}

// MARK: Building blocks

/// Cycles through the phases forever; with Reduce Motion it shows the last one, the outcome.
private struct Looping<Phase: Equatable, Content: View>: View {
    let phases: [Phase]
    let animation: (Phase) -> Animation?
    @ViewBuilder let content: (Phase) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ phases: [Phase],
        animation: @escaping (Phase) -> Animation?,
        @ViewBuilder content: @escaping (Phase) -> Content
    ) {
        self.phases = phases
        self.animation = animation
        self.content = content
    }

    var body: some View {
        if reduceMotion, let outcome = phases.last {
            content(outcome)
        } else {
            PhaseAnimator(phases, content: content, animation: animation)
        }
    }
}

/// A Pulse window in miniature: a sidebar of tabs beside a page.
struct MiniWindow<Page: View, AddressAccessory: View>: View {
    var theme = SpaceTheme.purple
    var activeRow: Int? = 0
    var dimmedRow: Int?
    @ViewBuilder var page: Page
    @ViewBuilder var addressAccessory: AddressAccessory

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().frame(width: 6, height: 6).opacity(0.25)
                    }
                }
                .frame(height: 12)
                HStack {
                    Spacer()
                    addressAccessory
                }
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Theme.pillFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                ForEach(0..<5, id: \.self) { row in
                    MiniTabRow(isActive: row == activeRow)
                        .opacity(row == dimmedRow ? 0.3 : 1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 118)
            .foregroundStyle(Theme.sidebarText)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding([.vertical, .trailing], 6)
        }
        .frame(width: 440, height: 220)
        .background(Theme.sidebarGradient(theme))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }
}

private struct MiniTabRow: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .frame(width: 10, height: 10)
                .opacity(0.35)
            Capsule()
                .frame(height: 4)
                .opacity(0.3)
        }
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(isActive ? Theme.activeTabFill : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .foregroundStyle(Theme.sidebarText)
    }
}

/// The lines of text on a page; they narrow with it in a split.
struct PageLines: View {
    var widths: [CGFloat] = [0.9, 1, 0.75, 0.95, 0.6]
    var hasHeadline = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if hasHeadline {
                Capsule().frame(maxWidth: 110, maxHeight: 8).opacity(0.35)
                    .padding(.bottom, 3)
            }
            ForEach(widths.indices, id: \.self) { index in
                Capsule().frame(maxWidth: 260 * widths[index], maxHeight: 5).opacity(0.18)
            }
        }
        .foregroundStyle(.primary)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ExtensionIcon: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4, style: .continuous)
            .fill(Color.orange.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "bolt.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
            }
    }
}
