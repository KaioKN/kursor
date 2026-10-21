import CoreGraphics
import XCTest
@testable import KursorCore

final class GestureSmootherTests: XCTestCase {
    func testStreamSumsToInputAndEnds() {
        let g = GestureSmoother(tau: 0.045, endDelay: 0.16)
        XCTAssertEqual(g.input(0.1, time: 0), [.began])
        XCTAssertEqual(g.input(0.1, time: 0.01), [])

        var total = 0.0
        var ended = false
        var t = 0.01
        while t < 1, !ended {
            t += 1.0 / 120
            for out in g.tick(time: t, dt: 1.0 / 120) {
                switch out {
                case let .changed(v): total += v
                case .ended: ended = true
                case .began: XCTFail("began twice")
                }
            }
        }
        XCTAssertTrue(ended)
        XCTAssertEqual(total, 0.2, accuracy: 1e-6)
        XCTAssertFalse(g.isActive)
    }

    func testFinishFlushesRemainder() {
        let g = GestureSmoother()
        _ = g.input(0.3, time: 0)
        XCTAssertEqual(g.finish(), [.changed(0.3), .ended])
        XCTAssertEqual(g.finish(), [])
    }
}

final class SmoothScrollerTests: XCTestCase {
    func drain(_ s: SmoothScroller) -> (Int, Int) {
        var x = 0, y = 0, frames = 0
        while s.isActive, frames < 1000 {
            let step = s.tick(dt: 1.0 / 120)
            x += Int(step.dx)
            y += Int(step.dy)
            frames += 1
        }
        return (x, y)
    }

    func testSlowNotchTravelsSpeedPixels() {
        let s = SmoothScroller(settings: .init(pixelsPerLine: 40, acceleration: 0.6, tau: 0.1))
        s.input(lines: CGVector(dx: 0, dy: 1), time: 0)
        let (x, y) = drain(s)
        XCTAssertEqual(x, 0)
        XCTAssertEqual(y, 40, accuracy: 1)
    }

    func testFastSpinAccelerates() {
        let s = SmoothScroller(settings: .init(pixelsPerLine: 40, acceleration: 1, tau: 0.1))
        for i in 0..<10 { s.input(lines: CGVector(dx: 0, dy: -1), time: Double(i) * 0.02) }
        let (_, y) = drain(s)
        XCTAssertLessThan(y, -400)
    }

    func testDirectionChangeStopsGlide() {
        let s = SmoothScroller(settings: .init(pixelsPerLine: 40, acceleration: 0, tau: 0.1))
        s.input(lines: CGVector(dx: 0, dy: 5), time: 0)
        _ = s.tick(dt: 1.0 / 120)
        s.input(lines: CGVector(dx: 0, dy: -1), time: 0.5)
        let (_, y) = drain(s)
        XCTAssertEqual(y, -40, accuracy: 1)
    }
}

final class MiddleButtonScrollTests: XCTestCase {
    let p = CGPoint(x: 50, y: 50)

    func testClickWithoutMovementStaysAClick() {
        let m = MiddleButtonScroll(mode: .pan)
        XCTAssertEqual(m.mouseDown(button: 2, location: p), .swallow)
        XCTAssertEqual(m.mouseDragged(button: 2, delta: CGVector(dx: 2, dy: 1)), .swallow)
        XCTAssertEqual(m.mouseUp(button: 2), .click(p))
    }

    func testDragPansAndSwallowsRelease() {
        let m = MiddleButtonScroll(mode: .pan, panSpeed: 1)
        _ = m.mouseDown(button: 2, location: p)
        XCTAssertEqual(m.mouseDragged(button: 2, delta: CGVector(dx: 0, dy: 10)), .scroll(CGVector(dx: 0, dy: 10)))
        XCTAssertEqual(m.mouseDragged(button: 2, delta: CGVector(dx: 0, dy: 3)), .scroll(CGVector(dx: 0, dy: 3)))
        XCTAssertEqual(m.mouseUp(button: 2), .swallow)
        XCTAssertNil(m.origin)
    }

    func testOtherButtonsUntouched() {
        let m = MiddleButtonScroll(mode: .pan)
        XCTAssertEqual(m.mouseDown(button: 0, location: p), .pass)
        XCTAssertEqual(m.mouseDragged(button: 0, delta: CGVector(dx: 20, dy: 0)), .pass)
        XCTAssertEqual(m.mouseUp(button: 0), .pass)
    }

    func testAutoscrollToggleAndExit() {
        let m = MiddleButtonScroll(mode: .autoscroll)
        _ = m.mouseDown(button: 2, location: p)
        XCTAssertEqual(m.mouseUp(button: 2), .swallow)
        XCTAssertTrue(m.isAutoscrolling)

        XCTAssertEqual(m.autoscrollStep(cursor: CGPoint(x: 50, y: 55), dt: 0.01), .zero) // dead zone
        let step = m.autoscrollStep(cursor: CGPoint(x: 50, y: 150), dt: 0.01)!
        XCTAssertLessThan(step.dy, 0) // cursor below anchor → scroll down

        XCTAssertEqual(m.mouseDown(button: 0, location: p), .swallow)
        XCTAssertFalse(m.isAutoscrolling)
        XCTAssertEqual(m.mouseUp(button: 0), .swallow)
        XCTAssertEqual(m.mouseDown(button: 0, location: p), .pass)
    }

    func testNormalModePassesMiddle() {
        let m = MiddleButtonScroll(mode: .normal)
        XCTAssertEqual(m.mouseDown(button: 2, location: p), .pass)
    }
}

final class GestureButtonTests: XCTestCase {
    func testHorizontalRepeatsVerticalOnce() {
        let g = GestureButton(threshold: 50)
        g.mouseDown(button: 3, location: .zero)
        XCTAssertNil(g.mouseDragged(button: 3, delta: CGVector(dx: -30, dy: 0)))
        XCTAssertEqual(g.mouseDragged(button: 3, delta: CGVector(dx: -30, dy: 5)), .left)
        XCTAssertNil(g.mouseDragged(button: 3, delta: CGVector(dx: -60, dy: 0)))
        XCTAssertEqual(g.mouseDragged(button: 3, delta: CGVector(dx: -60, dy: 0)), .left)
        XCTAssertEqual(g.mouseUp(button: 3), false)

        g.mouseDown(button: 3, location: .zero)
        XCTAssertEqual(g.mouseDragged(button: 3, delta: CGVector(dx: 0, dy: -70)), .up)
        XCTAssertNil(g.mouseDragged(button: 3, delta: CGVector(dx: 0, dy: -200)))
        XCTAssertNil(g.mouseDragged(button: 3, delta: CGVector(dx: 200, dy: 0)))
    }

    func testPressWithoutMovementIsClick() {
        let g = GestureButton(threshold: 50)
        g.mouseDown(button: 4, location: .zero)
        XCTAssertNil(g.mouseDragged(button: 4, delta: CGVector(dx: 5, dy: 5)))
        XCTAssertEqual(g.mouseUp(button: 4), true)
        XCTAssertNil(g.mouseUp(button: 4))
    }
}
