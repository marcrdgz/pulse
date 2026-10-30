import SwiftUI

/// Asks before an agent uses a tab, or before a click that may send, pay or delete: a one-line bar
/// at the bottom of that tab's page, answered with ↩ or Esc (see `BrowserWindow`'s key monitor).
struct AgentPrompt: View {
    let agent: Agent
    let request: AgentRequest

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.agentTint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // In full: the query is where a page would hide the user's data.
                if case .open(let url, _) = request.kind {
                    Text(Self.address(of: url))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .help(detail)
            Spacer(minLength: 16)
            Button(declineTitle) { agent.answer(request, allow: false) }
                .buttonStyle(KeyCapButtonStyle(key: "esc"))
            Button("Allow") { agent.answer(request, allow: true) }
                .buttonStyle(KeyCapButtonStyle(key: "↩", isProminent: true))
        }
        .font(.system(size: 13))
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .padding(.vertical, isAddress ? 8 : 0)
        .frame(width: isAddress ? 560 : 480)
        .frame(minHeight: 46)
        .background(.background, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
    }

    private var title: AttributedString {
        var name = AttributedString(agent.name)
        name.font = .system(size: 13, weight: .semibold)
        let action = switch request.kind {
        case .useTab(let site): " wants to use this tab on \(site)"
        case .confirm(let label, let site): " wants to click “\(label)” on \(site)"
        case .open(_, let signedIn): signedIn ? " wants to open, signed in as you:" : " wants to open:"
        }
        return name + AttributedString(action)
    }

    private var detail: String {
        switch request.kind {
        case .useTab: "It reads and acts here, signed in as you."
        case .confirm: "This may send, pay or delete something, or carry what it read to this site."
        case .open(_, let signedIn):
            (signedIn ? "It will use this site as you." : "It opens without your sign-ins.")
                + " Check the address: pages it read can hide your data in one."
        }
    }

    private var isAddress: Bool {
        if case .open = request.kind { true } else { false }
    }

    private var declineTitle: String {
        if case .useTab = request.kind { "Not Now" } else { "Don't Allow" }
    }

    /// Without the scheme, but with the query, where data would ride along.
    private static func address(of url: URL) -> String {
        let address = url.absoluteString.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: .regularExpression)
        return address.hasSuffix("/") ? String(address.dropLast()) : address
    }
}

/// What the agent is doing in the tab, in a dark bar at the bottom of the page; ⌘. takes the tab back.
struct AgentDock: View {
    let agent: Agent
    let tab: Tab
    let activity: AgentActivity

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.isDone ? "checkmark.circle.fill" : "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.agentTint)
                .symbolEffect(.pulse, isActive: !activity.isDone)
            Text(activity.status)
                .lineLimit(1)
                .truncationMode(.tail)
            if !activity.isDone {
                Button("Take Over") { agent.takeOver(tab) }
                    .buttonStyle(KeyCapButtonStyle(key: "⌘."))
                    .help("Stop \(agent.name) from using this tab")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.leading, 16)
        .padding(.trailing, activity.isDone ? 18 : 7)
        .frame(height: 46)
        .background(Color(white: 0.14).opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
        // The bar is dark in either appearance, so its controls draw as on a dark background.
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: 520)
    }
}

/// A rounded button that shows the key it answers to, so the bar reads at a glance.
private struct KeyCapButtonStyle: ButtonStyle {
    let key: String
    var isProminent = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Text(key)
                .font(.system(size: 11, weight: .medium))
                .opacity(0.75)
                .padding(.horizontal, 5)
                .frame(minWidth: 22, minHeight: 22)
                .background(.white.opacity(isProminent ? 0.2 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .background(.primary.opacity(isProminent ? 0 : 0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(height: 32)
        .background(fill(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
    }

    private func fill(isPressed: Bool) -> AnyShapeStyle {
        let emphasis = isPressed ? 2.0 : isHovered ? 1.0 : 0
        if isProminent { return AnyShapeStyle(Theme.agentTint.opacity(1 - emphasis * 0.08)) }
        return AnyShapeStyle(.primary.opacity(0.06 + emphasis * 0.04))
    }
}
