import CoreGraphics
import XCTest
@testable import KursorCore

final class FocusFollowerTests: XCTestCase {
    typealias W = FocusFollower.WindowInfo

    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let point = CGPoint(x: 500, y: 500)
    let editor = W(windowID: 10, pid: 100, bounds: CGRect(x: 0, y: 25, width: 1200, height: 900), owner: "Code")
    let browser = W(windowID: 20, pid: 200, bounds: CGRect(x: 300, y: 25, width: 1600, height: 1000), owner: "Safari")

    func testPicksTopmostNormalWindow() {
        let target = FocusFollower.target(at: point, in: [browser, editor], screen: screen, visibleArea: nil)
        XCTAssertEqual(target?.windowID, 20)
    }

    func testMenusAndDockKeepFocus() {
        let menu = W(windowID: 1, pid: 300, bounds: CGRect(x: 450, y: 450, width: 200, height: 300), layer: 101, owner: "Safari")
        XCTAssertNil(FocusFollower.target(at: point, in: [menu, browser], screen: screen, visibleArea: nil))

        let menuBar = W(windowID: 2, pid: 0, bounds: CGRect(x: 0, y: 0, width: 1920, height: 25), layer: 24, owner: "Window Server")
        XCTAssertNil(FocusFollower.target(at: CGPoint(x: 10, y: 10), in: [menuBar, browser], screen: screen, visibleArea: nil))
    }

    func testLooksThroughFullScreenOverlays() {
        let overlay = W(windowID: 3, pid: 400, bounds: screen, layer: 25, owner: "SomeOverlay")
        XCTAssertEqual(FocusFollower.target(at: point, in: [overlay, browser], screen: screen, visibleArea: nil)?.windowID, 20)
    }

    func testDockFullScreenWindowIsLookedThrough() {
        // macOS keeps a transparent full-screen Dock window (layer 20) on the Dock's display.
        let dock = W(windowID: 4, pid: 500, bounds: screen, layer: 20, owner: "Dock")
        XCTAssertEqual(FocusFollower.target(at: point, in: [dock, browser], screen: screen, visibleArea: nil)?.windowID, 20)
    }

    func testMenuBarAndDockAreaAreExcluded() {
        let visible = CGRect(x: 0, y: 30, width: 1920, height: 980) // menu bar on top, Dock at the bottom
        let windows = [browser, editor]
        XCTAssertNil(FocusFollower.target(at: CGPoint(x: 500, y: 1050), in: windows, screen: screen, visibleArea: visible))
        XCTAssertNil(FocusFollower.target(at: CGPoint(x: 500, y: 10), in: windows, screen: screen, visibleArea: visible))
        XCTAssertEqual(FocusFollower.target(at: point, in: windows, screen: screen, visibleArea: visible)?.windowID, 20)
    }

    func testMainDisplayWithDockAndOverlays() {
        // A main-display stack that used to block focusing: a screenshot tool's invisible
        // overlay, the Dock's full-screen window, then normal windows.
        let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let overlay = W(windowID: 30, pid: 700, bounds: main, layer: 1001, alpha: 0, owner: "ScreenshotTool")
        let dock = W(windowID: 31, pid: 500, bounds: main, layer: 20, owner: "Dock")
        let code = W(windowID: 32, pid: 800, bounds: CGRect(x: 0, y: 30, width: 2560, height: 1348), owner: "Code")
        let visible = CGRect(x: 0, y: 30, width: 2560, height: 1348)
        let target = FocusFollower.target(at: CGPoint(x: 777, y: 1259), in: [overlay, dock, code], screen: main, visibleArea: visible)
        XCTAssertEqual(target?.windowID, 32)
    }

    func testIgnoresInvisibleAndTinyWindows() {
        let hidden = W(windowID: 5, pid: 600, bounds: screen, alpha: 0)
        let tooltip = W(windowID: 6, pid: 200, bounds: CGRect(x: 495, y: 495, width: 30, height: 16))
        XCTAssertEqual(FocusFollower.target(at: point, in: [hidden, browser], screen: screen, visibleArea: nil)?.windowID, 20)
        XCTAssertNil(FocusFollower.target(at: point, in: [tooltip, browser], screen: screen, visibleArea: nil))
    }

    func testDesktopUnderCursorDoesNothing() {
        XCTAssertNil(FocusFollower.target(at: CGPoint(x: 1910, y: 1070), in: [browser, editor], screen: screen, visibleArea: nil))
    }

    func testAlreadyFocusedDetection() {
        let otherBrowserWindow = W(windowID: 21, pid: 200, bounds: CGRect(x: 1920, y: 0, width: 800, height: 600))
        let windows = [otherBrowserWindow, browser, editor]
        // Same app, but a different window of it is on top: still needs focusing.
        XCTAssertFalse(FocusFollower.isFocused(browser, in: windows, frontmostPID: 200))
        XCTAssertTrue(FocusFollower.isFocused(otherBrowserWindow, in: windows, frontmostPID: 200))
        XCTAssertFalse(FocusFollower.isFocused(editor, in: windows, frontmostPID: 200))
    }

    func testFocusSettingsDefaults() throws {
        let config = try JSONDecoder().decode(KursorConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(config.focus.mode, .displayChange)
        XCTAssertEqual(config.focus.delayMs, 120)
    }
}
