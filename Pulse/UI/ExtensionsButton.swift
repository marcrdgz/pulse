import AppKit
import SwiftUI
import WebKit

/// Arc's extensions menu: each extension's toolbar action, plus adding and managing extensions.
struct ExtensionsButton: View {
    let extensions: WebExtensions
    @Environment(Browser.self) private var browser
    @State private var isMenuPresented = false
    /// Where extension popups point, since WebKit shows them as AppKit popovers.
    @State private var anchor = PopoverAnchor()

    var body: some View {
        Button { isMenuPresented.toggle() } label: {
            Image(systemName: "puzzlepiece.extension")
        }
        .accessibilityLabel("Extensions")
        .help("Extensions")
        .background(PopoverAnchorView(anchor: anchor))
        .popover(isPresented: $isMenuPresented, arrowEdge: .bottom) {
            menu.presentationBackground(.thickMaterial)
        }
    }

    private var menu: some View {
        let _ = extensions.actionRevision
        let tab = browser.activeTab
        return VStack(alignment: .leading, spacing: 2) {
            if extensions.contexts.isEmpty {
                Text("Add extensions from the Chrome Web Store.")
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            ForEach(extensions.contexts, id: \.uniqueIdentifier) { context in
                let action = context.action(for: tab)
                MenuRow(
                    title: action?.label.nonEmpty ?? context.webExtension.displayName ?? "Extension",
                    icon: action?.icon(for: CGSize(width: 16, height: 16)) ?? context.webExtension.icon(for: CGSize(width: 16, height: 16)),
                    badge: action?.badgeText.nonEmpty
                ) {
                    perform(context, in: tab)
                }
                .disabled(action?.isEnabled == false)
            }
            if let tab, let id = ChromeWebStore.extensionID(fromStorePage: tab.url) {
                MenuRow(title: "Add This Extension", symbol: "plus.circle") {
                    isMenuPresented = false
                    Task { await extensions.install(.chromeWebStore(id: id)) }
                }
            }
            Divider().padding(.vertical, 4)
            MenuRow(title: "Get Extensions…", symbol: "bag") {
                isMenuPresented = false
                browser.openTab(url: ChromeWebStore.homeURL)
            }
            MenuRow(title: "Install from File…", symbol: "folder") {
                isMenuPresented = false
                extensions.chooseAndInstall()
            }
            SettingsLink {
                Label("Manage Extensions…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(MenuRowStyle())
        }
        .padding(6)
        .frame(width: 260)
    }

    private func perform(_ context: WKWebExtensionContext, in tab: Tab?) {
        isMenuPresented = false
        // An AppKit popover shown while this one closes is dismissed along with it.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            extensions.performAction(of: context, in: tab, from: anchor.view)
        }
    }
}

private struct MenuRow: View {
    let title: String
    var icon: NSImage?
    var symbol: String?
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                } else if let symbol {
                    Image(systemName: symbol).frame(width: 16, height: 16)
                }
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
            }
        }
        .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(label: configuration.label)
    }

    private struct HoverRow<Label: View>: View {
        let label: Label
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered && isEnabled ? Color.primary.opacity(0.08) : .clear)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

final class PopoverAnchor {
    weak var view: NSView?
}

private struct PopoverAnchorView: NSViewRepresentable {
    let anchor: PopoverAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
