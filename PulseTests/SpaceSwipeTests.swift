import AppKit
import Observation
import Synchronization
import Testing
@testable import Pulse

struct SpaceSwipeTests {
    private let tracker = SpaceSwipeTracker()
    private let pageWidth: CGFloat = 200

    /// A trackpad scroll event; `dx` is negative when the fingers move left.
    private func scroll(_ phase: CGScrollPhase, dx: Int32 = 0, dy: Int32 = 0) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        return NSEvent(cgEvent: event)!
    }

    @discardableResult
    private func send(_ phase: CGScrollPhase, dx: Int32 = 0, dy: Int32 = 0) -> Int? {
        tracker.track(scroll(phase, dx: dx, dy: dy), pageWidth: pageWidth)
    }

    /// The sidebar reads the position before any swipe; it must redraw as the fingers move, not on lift.
    @Test func theSpacesFollowTheFingersMidSwipe() {
        let redraws = Mutex(false)
        withObservationTracking {
            _ = tracker.position(from: 0, spaceCount: 2)
        } onChange: {
            redraws.withLock { $0 = true }
        }

        send(.began)
        send(.changed, dx: -50)

        #expect(redraws.withLock { $0 })
        #expect(tracker.position(from: 0, spaceCount: 2) == 0.25)
    }

    @Test func liftingPastAThirdSwitchesAndAShortDragSnapsBack() {
        send(.began)
        send(.changed, dx: -80)
        #expect(send(.ended) == 1)

        send(.began)
        send(.changed, dx: 20)
        #expect(send(.ended) == 0)
    }

    @Test func verticalScrollingIsLeftToTheSidebar() {
        send(.began)
        let event = scroll(.changed, dx: -3, dy: 30)
        _ = tracker.track(event, pageWidth: pageWidth)

        #expect(!tracker.consumes(event))
        #expect(tracker.position(from: 0, spaceCount: 2) == 0)
        #expect(send(.ended) == nil)
    }
}
