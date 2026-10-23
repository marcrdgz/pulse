import WebKit

/// Whether a page is audible, and muting it, like Safari's tab speaker. WebKit only offers
/// pausing publicly, so this uses the SPI Safari relies on (`_isPlayingAudio`, `_setPageMuted:`),
/// checked at runtime: without it there's simply no indicator and muting does nothing.
enum PageAudio {
    private static let playingAudioKey = "_isPlayingAudio"
    private static let setPageMuted = NSSelectorFromString("_setPageMuted:")
    /// `WKMediaAudioMuted`; capture muting uses other bits, which `_setPageMuted:` leaves as they are.
    private static let audioMutedState: UInt = 1 << 0

    /// Calls `onChange` with the page's audible state now and whenever it changes.
    static func observe(_ webView: WKWebView, onChange: @escaping @MainActor (Bool) -> Void) -> NSObject? {
        guard webView.responds(to: NSSelectorFromString(playingAudioKey)) else { return nil }
        return Observation(webView: webView, keyPath: playingAudioKey, onChange: onChange)
    }

    static func setMuted(_ isMuted: Bool, in webView: WKWebView) {
        guard webView.responds(to: setPageMuted) else { return }
        typealias SetPageMuted = @convention(c) (AnyObject, Selector, UInt) -> Void
        let implementation = unsafeBitCast(webView.method(for: setPageMuted), to: SetPageMuted.self)
        implementation(webView, setPageMuted, isMuted ? audioMutedState : 0)
    }

    /// String-keyed KVO, since the property isn't visible to Swift key paths; stops with its owner.
    private nonisolated final class Observation: NSObject, @unchecked Sendable {
        private weak var webView: WKWebView?
        private let keyPath: String
        private let onChange: @MainActor (Bool) -> Void

        @MainActor
        init(webView: WKWebView, keyPath: String, onChange: @escaping @MainActor (Bool) -> Void) {
            self.webView = webView
            self.keyPath = keyPath
            self.onChange = onChange
            super.init()
            webView.addObserver(self, forKeyPath: keyPath, options: [.initial, .new], context: nil)
        }

        deinit {
            webView?.removeObserver(self, forKeyPath: keyPath)
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            let isPlaying = change?[.newKey] as? Bool ?? false
            MainActor.assumeIsolated { onChange(isPlaying) }
        }
    }
}
