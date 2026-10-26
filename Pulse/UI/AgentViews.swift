import SwiftUI

/// Asks before an agent uses a tab, or before a click that may send, pay or delete; shown over that tab.
struct AgentPrompt: View {
    let agent: Agent
    let request: AgentRequest

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.agentTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(declineTitle) { agent.answer(request, allow: false) }
                .keyboardShortcut(.cancelAction)
            Button("Allow") { agent.answer(request, allow: true) }
                .keyboardShortcut(.defaultAction)
                .tint(Theme.agentTint)
        }
        .fixedSize(horizontal: true, vertical: false)
        .controlSize(.large)
        .padding(14)
        .frame(minWidth: 460)
        // Opaque: over a bright page, a material washes the secondary line out.
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }

    private var title: AttributedString {
        var name = AttributedString(agent.name)
        name.font = .system(size: 13, weight: .semibold)
        return switch request.kind {
        case .useTab: name + AttributedString(" wants to use this tab")
        case .confirm(let label): name + AttributedString(" wants to click “\(label)”")
        }
    }

    private var detail: String {
        switch request.kind {
        case .useTab: "It reads and acts here, signed in as you."
        case .confirm: "This may send, pay or delete something."
        }
    }

    private var declineTitle: String {
        request.kind == .useTab ? "Not Now" : "Don't Allow"
    }
}

/// What the agent is doing in the tab, at the bottom of the page; the user can take the tab back.
struct AgentDock: View {
    let agent: Agent
    let tab: Tab
    let activity: AgentActivity

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: activity.isDone ? "checkmark.circle.fill" : "sparkles")
                .foregroundStyle(Theme.agentTint)
                .symbolEffect(.pulse, isActive: !activity.isDone)
            Text(activity.status)
                .lineLimit(1)
                .truncationMode(.tail)
            if !activity.isDone {
                Button("Take Over") { agent.takeOver(tab) }
                    .buttonStyle(.borderless)
                    .help("Stop \(agent.name) from using this tab")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .frame(maxWidth: 520)
        .padding(.bottom, 16)
    }
}
