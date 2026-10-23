import SwiftUI

/// Shown over a tab whose page failed to load, instead of a blank card.
struct LoadErrorView: View {
    let tab: Tab
    let error: Tab.LoadError

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: error.isOffline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(error.isOffline ? "You're offline" : "This page couldn't load")
                .font(.system(size: 20, weight: .semibold))
            Text(error.message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Text(error.url.displayHost ?? error.url.absoluteString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)
            Button("Try Again") { tab.reload() }
                .controlSize(.large)
                .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
