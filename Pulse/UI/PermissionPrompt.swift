import SwiftUI

/// Chrome's permission bubble: shown over the page of the tab that asked.
struct PermissionPrompt: View {
    @Environment(Browser.self) private var browser
    let request: PermissionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: request.kinds.contains(.camera) ? "video.fill" : "mic.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Text(request.origin).bold()) wants to")
                    Text(description)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13))
            }
            VStack(spacing: 6) {
                choice("Allow while visiting the site", .allowAlways)
                choice("Allow this time", .allowOnce)
                choice("Never allow", .neverAllow)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
    }

    private var description: String {
        switch (request.kinds.contains(.camera), request.kinds.contains(.microphone)) {
        case (true, true): "Use your camera and microphone"
        case (true, false): "Use your camera"
        default: "Use your microphone"
        }
    }

    private func choice(_ title: String, _ choice: PermissionChoice) -> some View {
        Button { browser.answer(request, with: choice) } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }
}

/// Chrome's "not your default browser" infobar, shown on launch until acted on or dismissed.
struct DefaultBrowserBanner: View {
    @AppStorage("defaultBrowserBannerDismissed") private var isDismissed = false
    @State private var isDefault = DefaultBrowser.isDefault

    var body: some View {
        if !isDismissed, !isDefault {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text("Pulse isn't your default browser")
                Spacer()
                Button("Make Default") {
                    Task {
                        await DefaultBrowser.makeDefault()
                        isDefault = DefaultBrowser.isDefault
                    }
                }
                Button { isDismissed = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(SidebarIconButtonStyle())
                .help("Don't show again")
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
