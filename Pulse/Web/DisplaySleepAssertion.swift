import Foundation
import IOKit.pwr_mgt

/// Keeps the display (and so the Mac) from idling to sleep while alive. WebKit's own sleep
/// disabler doesn't reliably take hold in this app (a fullscreen Twitch stream dimmed and slept
/// mid-watch), so Pulse holds the assertion itself.
final class DisplaySleepAssertion {
    private var id: IOPMAssertionID = 0

    init?(reason: String) {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return nil }
    }

    deinit {
        IOPMAssertionRelease(id)
    }
}
