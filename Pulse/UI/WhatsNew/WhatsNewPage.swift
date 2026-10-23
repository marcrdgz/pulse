import SwiftUI

/// pulse://whats-new: the latest release up top, earlier releases below. It follows the site's
/// brand: the Halo mark draws itself once, and the summary is the headline, ending in the flare.
struct WhatsNewPage: View {
    var releases: [ReleaseNotes] = ReleaseNotes.bundled
    /// Whether the column has room for the change lists side by side; a split pane may not.
    @State private var isWide = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                if let latest = releases.first {
                    header(latest)
                    highlights(of: latest)
                    changes(in: latest)
                }
                if releases.count > 1 {
                    earlierReleases
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: 720, alignment: .leading)
            .onGeometryChange(for: Bool.self) { $0.size.width >= 600 } action: { isWide = $0 }
            .padding(.horizontal, 32)
            .padding(.top, 64)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity)
        }
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
    }

    private func header(_ release: ReleaseNotes) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HaloMark(size: 64, drawsIn: true)
                .padding(.leading, -6)
            FlareHeadline(text: release.summary)
                .font(.system(size: 44, weight: .bold))
                .tracking(-1.1)
                .fixedSize(horizontal: false, vertical: true)
            Text("Pulse \(release.version), released \(release.date.formatted(date: .long, time: .omitted))")
                .font(.system(size: 15))
                .foregroundStyle(Brand.dim)
        }
    }

    /// Highlights with a scene get a stage to play on; the rest read as a compact list after them.
    private func highlights(of release: ReleaseNotes) -> some View {
        let shown = release.highlights.filter { $0.scene != nil }
        let told = release.highlights.filter { $0.scene == nil }
        return VStack(alignment: .leading, spacing: 48) {
            ForEach(shown) { highlight in
                if let scene = highlight.scene {
                    StagedHighlight(highlight: highlight, scene: scene)
                }
            }
            if !told.isEmpty {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(told) { CompactHighlight(highlight: $0) }
                }
            }
        }
    }

    private func changes(in release: ReleaseNotes) -> some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 40))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 40))
        return layout {
            if !release.improvements.isEmpty {
                ChangeList(title: "Also new", items: release.improvements)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if !release.fixes.isEmpty {
                ChangeList(title: "Fixed", items: release.fixes)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.top, 32)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private var earlierReleases: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Earlier releases")
                .font(.system(size: 20, weight: .semibold))
            ForEach(releases.dropFirst()) { release in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(release.summary)
                            .font(.system(size: 15))
                        ChangeList(title: "New", items: release.highlights.map(\.title) + release.improvements)
                        if !release.fixes.isEmpty {
                            ChangeList(title: "Fixed", items: release.fixes)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.leading, 4)
                } label: {
                    let date = Text(release.date.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(Brand.dim)
                    Text("\(Text("Pulse \(release.version)").fontWeight(.medium))   \(date)")
                        .font(.system(size: 15))
                }
            }
        }
    }
}

/// A headline whose closing period is the flare, like the site's headings.
private struct FlareHeadline: View {
    let text: String

    var body: some View {
        if text.hasSuffix(".") {
            let period = Text(".").foregroundStyle(Brand.flare)
            Text("\(String(text.dropLast()))\(period)")
        } else {
            Text(text)
        }
    }
}

private struct StagedHighlight: View {
    let highlight: ReleaseNotes.Highlight
    let scene: WhatsNewScene

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Scenes are drawn at 440 × 220 and scaled to the stage, down to a narrow split pane.
            GeometryReader { proxy in
                WhatsNewSceneView(scene: scene)
                    .scaleEffect(min(1.25, (proxy.size.width - 64) / 440))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(height: 340)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(highlight.title)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.3)
                Spacer(minLength: 0)
                if let shortcut = highlight.shortcut {
                    Keycaps(shortcut: shortcut)
                }
            }
            Text(highlight.body)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Brand.dim)
                .frame(maxWidth: 560, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CompactHighlight: View {
    let highlight: ReleaseNotes.Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: highlight.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Brand.accent)
                .frame(width: 44, height: 44)
                .background(Brand.card, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(highlight.title)
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                    if let shortcut = highlight.shortcut {
                        Keycaps(shortcut: shortcut)
                    }
                }
                Text(highlight.body)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(Brand.dim)
                    .frame(maxWidth: 560, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }
}

private struct ChangeList: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Brand.flare)
                        .frame(width: 5, height: 5)
                        .padding(.top, 8)
                    Text(item)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 14))
    }
}

/// A shortcut as the keys to press, like the site's shortcut table.
private struct Keycaps: View {
    let shortcut: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(shortcut.enumerated()), id: \.offset) { _, key in
                Text(String(key))
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Brand.card, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Brand.line))
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Brand.line)
                            .offset(y: 2)
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut)
    }
}
