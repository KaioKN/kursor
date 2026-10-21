import CoreGraphics
import XCTest
@testable import KursorCore

final class ClickStabilizerTests: XCTestCase {
    let origin = CGPoint(x: 100, y: 100)

    func makeStabilizer(cursorPinned: Bool = false) -> ClickStabilizer {
        ClickStabilizer(settings: .init(enabled: true, radius: 4, maxDuration: 0.2, cursorPinned: cursorPinned))
    }

    func testCleanClick() {
        let s = makeStabilizer()
        XCTAssertEqual(s.mouseDown(button: 0, location: origin, time: 0, stabilize: true), .pass)
        let (decision, record) = s.mouseUp(button: 0, location: origin, time: 0.08)
        XCTAssertEqual(decision, .relocate(origin))
        XCTAssertEqual(record?.outcome, .clean)
    }

    func testMicroDragIsSwallowedAndReleaseLandsOnPressPoint() {
        let s = makeStabilizer()
        _ = s.mouseDown(button: 0, location: origin, time: 0, stabilize: true)
        XCTAssertEqual(s.mouseDragged(button: 0, location: CGPoint(x: 102, y: 101), delta: CGVector(dx: 2, dy: 1), time: 0.03), .swallow)
        XCTAssertEqual(s.mouseDragged(button: 0, location: CGPoint(x: 103, y: 102), delta: CGVector(dx: 1, dy: 1), time: 0.06), .swallow)
        let (decision, record) = s.mouseUp(button: 0, location: CGPoint(x: 103, y: 102), time: 0.1)
        XCTAssertEqual(decision, .relocate(origin))
        XCTAssertEqual(record?.outcome, .stabilized)
        XCTAssertEqual(record?.swallowed, 2)
        XCTAssertEqual(record?.maxDistance ?? 0, hypot(3, 2), accuracy: 0.001)
    }

    func testLeavingRadiusStartsRealDragWithFullDelta() {
        let s = makeStabilizer()
        _ = s.mouseDown(button: 0, location: origin, time: 0, stabilize: true)
        XCTAssertEqual(s.mouseDragged(button: 0, location: CGPoint(x: 102, y: 100), delta: CGVector(dx: 2, dy: 0), time: 0.02), .swallow)
        XCTAssertEqual(
            s.mouseDragged(button: 0, location: CGPoint(x: 106, y: 100), delta: CGVector(dx: 4, dy: 0), time: 0.04),
            .release(location: CGPoint(x: 106, y: 100), delta: CGVector(dx: 6, dy: 0))
        )
        XCTAssertEqual(s.mouseDragged(button: 0, location: CGPoint(x: 120, y: 100), delta: CGVector(dx: 14, dy: 0), time: 0.06), .pass)
        let (decision, record) = s.mouseUp(button: 0, location: CGPoint(x: 120, y: 100), time: 0.3)
        XCTAssertEqual(decision, .pass)
        XCTAssertEqual(record?.outcome, .drag)
    }

    func testSlowDeliberateDragAfterWindowPassesImmediately() {
        let s = makeStabilizer()
        _ = s.mouseDown(button: 0, location: origin, time: 0, stabilize: true)
        // Holding still past the window, then moving 1 px: text selection must start.
        XCTAssertEqual(
            s.mouseDragged(button: 0, location: CGPoint(x: 101, y: 100), delta: CGVector(dx: 1, dy: 0), time: 0.5),
            .release(location: CGPoint(x: 101, y: 100), delta: CGVector(dx: 1, dy: 0))
        )
    }

    func testIneligibleButtonIsOnlyMeasured() {
        let s = makeStabilizer()
        _ = s.mouseDown(button: 1, location: origin, time: 0, stabilize: false)
        XCTAssertEqual(s.mouseDragged(button: 1, location: CGPoint(x: 102, y: 100), delta: CGVector(dx: 2, dy: 0), time: 0.03), .pass)
        let (decision, record) = s.mouseUp(button: 1, location: CGPoint(x: 102, y: 100), time: 0.09)
        XCTAssertEqual(decision, .pass)
        XCTAssertEqual(record?.outcome, .microDrag)
    }

    func testPinnedCursorReleasesAtAccumulatedPosition() {
        let s = makeStabilizer(cursorPinned: true)
        _ = s.mouseDown(button: 0, location: origin, time: 0, stabilize: true)
        // Cursor is warped back, so locations stay at the origin; only deltas tell the truth.
        XCTAssertEqual(s.mouseDragged(button: 0, location: origin, delta: CGVector(dx: 3, dy: 0), time: 0.02), .swallow)
        XCTAssertEqual(
            s.mouseDragged(button: 0, location: origin, delta: CGVector(dx: 3, dy: 0), time: 0.04),
            .release(location: CGPoint(x: 106, y: 100), delta: CGVector(dx: 6, dy: 0))
        )
    }

    func testMovementCountsEvenWhenCursorDidNotFollow() {
        let s = makeStabilizer()
        // Swallowed drags may leave the cursor in place: locations stay put, deltas grow.
        XCTAssertEqual(s.mouseDown(button: 0, location: origin, time: 0, stabilize: true), .pass)
        XCTAssertEqual(s.mouseDragged(button: 0, location: CGPoint(x: 101, y: 100), delta: CGVector(dx: 3, dy: 0), time: 0.02), .swallow)
        XCTAssertEqual(
            s.mouseDragged(button: 0, location: CGPoint(x: 102, y: 100), delta: CGVector(dx: 3, dy: 0), time: 0.04),
            .release(location: CGPoint(x: 102, y: 100), delta: CGVector(dx: 2, dy: 0))
        )
    }

    func testDoubleClickIsTwoIndependentClicks() {
        let s = makeStabilizer()
        for t in [0.0, 0.15] {
            _ = s.mouseDown(button: 0, location: origin, time: t, stabilize: true)
            XCTAssertEqual(s.mouseDragged(button: 0, location: CGPoint(x: 101, y: 100), delta: CGVector(dx: 1, dy: 0), time: t + 0.02), .swallow)
            XCTAssertEqual(s.mouseUp(button: 0, location: CGPoint(x: 101, y: 100), time: t + 0.05).0, .relocate(origin))
        }
    }

    func testSecondButtonStopsInterfering() {
        let s = makeStabilizer()
        _ = s.mouseDown(button: 0, location: origin, time: 0, stabilize: true)
        _ = s.mouseDown(button: 1, location: origin, time: 0.01, stabilize: true)
        XCTAssertEqual(s.mouseDragged(button: 0, location: CGPoint(x: 101, y: 100), delta: CGVector(dx: 1, dy: 0), time: 0.02), .pass)
    }
}

final class DebouncerTests: XCTestCase {
    func testBounceIsSwallowedWithItsRelease() {
        let d = Debouncer(window: 0.03)
        XCTAssertTrue(d.mouseDown(button: 0, time: 0))
        XCTAssertTrue(d.mouseUp(button: 0, time: 0.08))
        XCTAssertFalse(d.mouseDown(button: 0, time: 0.09))
        XCTAssertFalse(d.mouseUp(button: 0, time: 0.095))
        XCTAssertEqual(d.bouncesFiltered, 1)
    }

    func testFastDoubleClickSurvives() {
        let d = Debouncer(window: 0.03)
        XCTAssertTrue(d.mouseDown(button: 0, time: 0))
        XCTAssertTrue(d.mouseUp(button: 0, time: 0.06))
        XCTAssertTrue(d.mouseDown(button: 0, time: 0.14))
        XCTAssertTrue(d.mouseUp(button: 0, time: 0.2))
    }

    func testButtonsAreIndependent() {
        let d = Debouncer(window: 0.03)
        XCTAssertTrue(d.mouseUp(button: 0, time: 0))
        XCTAssertTrue(d.mouseDown(button: 1, time: 0.01))
    }
}

final class StuckButtonGuardTests: XCTestCase {
    func testReleasesOnlyAfterGrace() {
        let g = StuckButtonGuard(grace: 0.4)
        g.delivered(down: 0, time: 0)
        XCTAssertEqual(g.check(time: 0.25) { _ in true }, [])
        XCTAssertEqual(g.check(time: 0.5) { _ in false }, [])
        XCTAssertEqual(g.check(time: 0.75) { _ in false }, [])
        XCTAssertEqual(g.check(time: 0.9) { _ in false }, [0])
        XCTAssertFalse(g.hasPressedButtons)
        XCTAssertEqual(g.releasesSynthesized, 1)
    }

    func testHardwareDownResetsTheClock() {
        let g = StuckButtonGuard(grace: 0.4)
        g.delivered(down: 0, time: 0)
        _ = g.check(time: 0.25) { _ in false }
        _ = g.check(time: 0.5) { _ in true }
        XCTAssertEqual(g.check(time: 0.75) { _ in false }, [])
    }

    func testNormalReleaseClearsTracking() {
        let g = StuckButtonGuard()
        g.delivered(down: 0, time: 0)
        g.delivered(up: 0)
        XCTAssertFalse(g.hasPressedButtons)
        XCTAssertEqual(g.check(time: 5) { _ in false }, [])
    }
}
