import Foundation
import Testing
import WebKit
@testable import Pulse

struct PageAudioTests {
    /// One second of a 440 Hz tone, too faint to hear, as a WAV data URL looped by the page.
    private var tone: String {
        let sampleRate = 8_000
        var samples = Data()
        for index in 0..<sampleRate {
            let value = Int16(sin(Double(index) * 2 * .pi * 440 / Double(sampleRate)) * 30)
            withUnsafeBytes(of: value.littleEndian) { samples.append(contentsOf: $0) }
        }
        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples.count))
        wav.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); append(UInt32(samples.count))
        wav.append(samples)
        return "data:audio/wav;base64," + wav.base64EncodedString()
    }

    @Test func detectsAudioAndMutesIt() async throws {
        let browser = Browser()
        let tab = browser.openTab(url: URL(string: "about:blank")!)
        // WebKit only loads media for web views in a window.
        let window = NSWindow(
            contentRect: NSRect(x: -2000, y: 0, width: 400, height: 300),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(tab.webView)
        window.orderBack(nil)
        defer { window.close() }
        tab.webView.loadHTMLString("<audio autoplay loop src='\(tone)'></audio>", baseURL: URL(string: "https://example.com"))
        try await waitUntil { tab.isPlayingAudio }
        #expect(tab.mediaDescription == "Playing audio")

        tab.toggleMuted()
        #expect(tab.isMuted)
        #expect(mutedState(of: tab.webView) == 1)
        #expect(tab.mediaDescription == "Muted")
    }

    @Test func staysMutedAfterSleeping() async throws {
        let browser = Browser()
        let tab = browser.openTab(url: URL(string: "about:blank")!)
        _ = tab.webView
        tab.toggleMuted()
        browser.openTab(url: URL(string: "about:blank")!)

        await browser.hibernateInactiveTabs(now: .now + 2 * 60 * 60)
        #expect(tab.isHibernated)
        #expect(mutedState(of: tab.webView) == 1)

        tab.toggleMuted()
        #expect(mutedState(of: tab.webView) == 0)
    }

    private func mutedState(of webView: WKWebView) -> UInt? {
        (webView.value(forKey: "_mediaMutedState") as? UInt).map { $0 & 1 }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition())
    }
}
