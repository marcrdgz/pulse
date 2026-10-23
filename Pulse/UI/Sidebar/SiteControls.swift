import SwiftUI
import WebKit

/// Arc's site controls, opened from the sliders in the address pill: the connection's security,
/// the site's camera and microphone, sound, ad blocking and its stored data.
struct SiteControls: View {
    @Environment(Browser.self) private var browser
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsPane.storageKey) private var settingsPane = SettingsPane.general
    let tab: Tab
    /// The store isn't observable, so the switches keep their own copy while the popover is open.
    @State private var decisions: [PermissionKind: Bool] = [:]
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            connection
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            VStack(spacing: 0) {
                ForEach(shownPermissions, id: \.self) { kind in
                    switchRow(kind == .camera ? "Camera" : "Microphone", symbol: kind == .camera ? "video" : "mic", isOn: permission(kind))
                }
                switchRow("Sound", symbol: tab.isMuted ? "speaker.slash" : "speaker.wave.2", isOn: sound)
                if browser.contentBlocker.isEnabled {
                    switchRow("Block Ads and Trackers", symbol: "shield", isOn: adBlocking)
                }
            }
            .padding(.vertical, 6)
            Divider()
            VStack(spacing: 0) {
                actionRow("Clear Cookies and Site Data…", symbol: "externaldrive") { isConfirmingClear = true }
                actionRow("Site Permissions", symbol: "hand.raised") {
                    settingsPane = .privacy
                    openSettings()
                    dismiss()
                }
            }
            .padding(6)
        }
        .font(.system(size: 13))
        .frame(width: 280)
        .onAppear(perform: loadDecisions)
        .confirmationDialog(
            "Clear cookies and site data for \(tab.url.displayHost ?? "this site")?",
            isPresented: $isConfirmingClear
        ) {
            Button("Clear", role: .destructive) {
                dismiss()
                Task { await browser.clearSiteData(for: tab) }
            }
        } message: {
            Text("You'll be signed out of this site.")
        }
    }

    private var connection: some View {
        // Mixed content (an http image on an https page) makes the connection only partly secure.
        let isSecure = tab.url.scheme == "https" && tab.loadedWebView?.hasOnlySecureContent != false
        return Label(
            isSecure ? "Connection is Secure" : "Connection is Not Secure",
            systemImage: isSecure ? "lock" : "lock.open"
        )
        .labelStyle(SiteControlLabelStyle())
        .foregroundStyle(isSecure ? .green : .orange)
    }

    /// Arc lists a device once the site has asked for it: decided before, or in use now.
    private var shownPermissions: [PermissionKind] {
        PermissionKind.allCases.filter { decisions[$0] != nil || captureState($0) != .none }
    }

    private func captureState(_ kind: PermissionKind) -> WKMediaCaptureState {
        kind == .camera ? tab.cameraCaptureState : tab.microphoneCaptureState
    }

    private func loadDecisions() {
        guard let origin = tab.url.permissionOrigin else { return }
        for kind in PermissionKind.allCases {
            decisions[kind] = browser.sitePermissions?.decision(for: origin, kinds: [kind])
        }
    }

    /// Without a saved decision, a page using the device was allowed once.
    private func permission(_ kind: PermissionKind) -> Binding<Bool> {
        Binding(
            get: { decisions[kind] ?? (captureState(kind) != .none) },
            set: { isAllowed in
                decisions[kind] = isAllowed
                browser.setPermission(isAllowed, for: kind, on: tab)
            }
        )
    }

    private var sound: Binding<Bool> {
        Binding(get: { !tab.isMuted }, set: { if $0 == tab.isMuted { tab.toggleMuted() } })
    }

    private var adBlocking: Binding<Bool> {
        Binding(
            get: { browser.contentBlocker.isBlocking(on: tab.url) },
            set: { if $0 != browser.contentBlocker.isBlocking(on: tab.url) { browser.toggleContentBlocking(on: tab) } }
        )
    }

    private func switchRow(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        // macOS packs a switch next to its label, so the row spreads them itself.
        HStack {
            Label(title, systemImage: symbol)
                .labelStyle(SiteControlLabelStyle())
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(SiteControlLabelStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SiteControlRowStyle())
    }
}

/// Icons in a fixed column so the titles line up, as in Arc's menu.
private struct SiteControlLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .font(.system(size: 14))
                .frame(width: 20)
            configuration.title
        }
    }
}

private struct SiteControlRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.iconHoverFill)
                        .opacity(isHovered ? 1 : 0)
                )
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { isHovered = $0 }
        }
    }
}
