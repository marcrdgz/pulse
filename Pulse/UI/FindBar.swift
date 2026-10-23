import SwiftUI

/// Floating ⌘F bar in the top-right corner of the page.
struct FindBar: View {
    @Environment(Browser.self) private var browser
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        @Bindable var browser = browser
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find on Page", text: $browser.findQuery)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onSubmit { browser.findInPage() }
                .onExitCommand(perform: browser.hideFindBar)
            if browser.isFindQueryMissing {
                Text("Not found")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Group {
                Button { browser.findInPage(backwards: true) } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityLabel("Previous Match")
                .help("Previous Match (⌘⇧G)")
                Button { browser.findInPage() } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Next Match")
                .help("Next Match (⌘G)")
                Button(action: browser.hideFindBar) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close Find Bar")
                .help("Close (esc)")
            }
            .buttonStyle(SidebarIconButtonStyle())
        }
        .font(.system(size: 13))
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.primary.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .onAppear { isFieldFocused = true }
        .onChange(of: browser.findBarActivation) { isFieldFocused = true }
        .onChange(of: browser.findQuery) { browser.findInPage() }
    }
}
