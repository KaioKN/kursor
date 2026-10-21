import XCTest
@testable import KursorCore

final class ConfigTests: XCTestCase {
    func testEmptyJSONGivesDefaults() throws {
        let config = try JSONDecoder().decode(KursorConfig.self, from: Data("{}".utf8))
        XCTAssertEqual(config, KursorConfig())
    }

    func testPartialAndUnknownValuesFallBack() throws {
        let json = """
        {"zoom": {"sensitivity": 2}, "profiles": [{"id": "default", "name": "X",
          "click": {"radius": 6}, "buttons": {"mappings": [{"button": 3, "action": "teleport"}]}}]}
        """
        let config = try JSONDecoder().decode(KursorConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.zoom.sensitivity, 2)
        XCTAssertEqual(config.zoom.modifiers, [.command])
        XCTAssertEqual(config.profiles[0].click.radius, 6)
        XCTAssertEqual(config.profiles[0].click.maxDurationMs, 200)
        XCTAssertEqual(config.profiles[0].buttons.action(for: 3), .none)
    }

    func testRoundTrip() throws {
        var config = KursorConfig()
        config.profiles[0].buttons.setAction(.gesture, for: 3)
        config.rotate.modifiers = [.control, .option]
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(KursorConfig.self, from: data), config)
    }

    func testMissingDefaultProfileIsRestored() throws {
        let json = #"{"profiles": [{"id": "t", "name": "T", "match": {"category": "trackpad"}}]}"#
        let config = try JSONDecoder().decode(KursorConfig.self, from: Data(json.utf8))
        XCTAssertTrue(config.profiles.contains { $0.match == nil })
    }

    func testProfileResolutionPrefersExactDevice() {
        var config = KursorConfig()
        var own = DeviceProfile(name: "Example", match: DeviceMatch(vendorID: 0x1234, productID: 0x5678))
        own.scroll.speed = 77
        config.profiles.append(own)

        let mouse = DeviceInfo(vendorID: 0x1234, productID: 0x5678, name: "Example Mouse", category: .mouse)
        let other = DeviceInfo(vendorID: 1, productID: 2, name: "Other", category: .mouse)
        let trackpad = DeviceInfo(vendorID: 0x5AC, productID: 0x281, name: "Apple Internal Keyboard / Trackpad", category: .trackpad)

        XCTAssertEqual(config.profile(for: mouse).scroll.speed, 77)
        XCTAssertEqual(config.profile(for: other).id, "default")
        XCTAssertEqual(config.profile(for: trackpad).id, "trackpad")
        XCTAssertEqual(config.profile(for: nil).id, "default")
    }

    func testCategoryGuess() {
        XCTAssertEqual(DeviceInfo.guessCategory(name: "Apple Internal Keyboard / Trackpad", vendorID: 0x5AC), .trackpad)
        XCTAssertEqual(DeviceInfo.guessCategory(name: "Example Wireless Mouse", vendorID: 0x1234), .mouse)
    }

    func testSpeedMappingMatchesLinearMouse() {
        XCTAssertEqual(PointerController.resolution(forSpeed: 0), 1200, accuracy: 0.001)
        XCTAssertEqual(PointerController.resolution(forSpeed: 1), 40, accuracy: 0.001)
        XCTAssertEqual(PointerController.resolution(forSpeed: 0.5909), 66.17, accuracy: 0.05)
    }
}

final class LinearMouseImporterTests: XCTestCase {
    func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "linearmouse", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testImportsDevices() throws {
        let result = try LinearMouseImporter.importConfig(data: fixture(), into: KursorConfig())
        let profiles = result.config.profiles

        let wireless = try XCTUnwrap(profiles.first { $0.match?.vendorID == 0x1234 && $0.match?.productID == 0x5678 })
        XCTAssertEqual(wireless.pointer.mode, .custom)
        XCTAssertEqual(wireless.pointer.speed, 0.5909, accuracy: 1e-6)
        XCTAssertEqual(wireless.pointer.acceleration, 0)
        XCTAssertTrue(wireless.scroll.reverseVertical)
        XCTAssertEqual(wireless.scroll.speed, 4.3 * 8, accuracy: 1e-6)

        let gaming = try XCTUnwrap(profiles.first { $0.match?.vendorID == 0x2345 })
        XCTAssertEqual(gaming.buttons.action(for: 3), .spaceLeft)
        XCTAssertEqual(gaming.buttons.action(for: 4), .spaceRight)
        // Mappings that need modifier keys have no equivalent and are skipped.
        XCTAssertEqual(gaming.buttons.action(for: 5), .none)

        // Two LinearMouse schemes for the same mouse merge into one profile;
        // the earlier "disableAcceleration" survives the later scheme.
        let basic = profiles.filter { $0.match?.vendorID == 0x4567 && $0.match?.productID == 0xDEF0 }
        XCTAssertEqual(basic.count, 1)
        XCTAssertEqual(basic.first?.pointer.mode, .linear)
        XCTAssertEqual(basic.first?.pointer.speed ?? 0, 0.0737, accuracy: 1e-6)

        // The trackpad scheme updates the built-in trackpad profile instead of adding one.
        XCTAssertEqual(profiles.filter { $0.match?.category == .trackpad }.count, 1)
        XCTAssertEqual(profiles.first { $0.id == "trackpad" }?.scroll.reverseVertical, false)

        XCTAssertEqual(result.skippedSchemes, 0)
        XCTAssertEqual(profiles.count, 2 + 4) // default + trackpad + wireless, gaming, office, basic
    }

    func testReimportIsIdempotent() throws {
        let once = try LinearMouseImporter.importConfig(data: fixture(), into: KursorConfig()).config
        let twice = try LinearMouseImporter.importConfig(data: fixture(), into: once).config
        XCTAssertEqual(once.profiles.count, twice.profiles.count)
    }

    func testLooseValues() {
        XCTAssertEqual(LinearMouseImporter.intValue("0x2345"), 0x2345)
        XCTAssertEqual(LinearMouseImporter.intValue(42), 42)
        XCTAssertEqual(LinearMouseImporter.mapAction("missionControl.spaceLeft"), .spaceLeft)
        XCTAssertNil(LinearMouseImporter.mapAction("something.else"))
    }
}

final class PointerDriftTests: XCTestCase {
    typealias Live = PointerController.LiveValues

    func testCustomSettingsMatch() {
        var s = PointerSettings()
        s.mode = .custom
        s.speed = 0.5909
        s.acceleration = 0
        let resolution = PointerController.resolution(forSpeed: 0.5909)
        XCTAssertTrue(PointerController.isApplied(s, current: Live(resolution: resolution, acceleration: 0, linear: nil), supportsLinear: false))
        // A mouse after waking from sleep: macOS defaults are back.
        XCTAssertFalse(PointerController.isApplied(s, current: Live(resolution: 400, acceleration: 0.6875, linear: nil), supportsLinear: false))
        XCTAssertFalse(PointerController.isApplied(s, current: Live(resolution: resolution, acceleration: 0.6875, linear: nil), supportsLinear: false))
        XCTAssertFalse(PointerController.isApplied(s, current: Live(resolution: resolution, acceleration: 0, linear: 1), supportsLinear: true))
    }

    func testLinearSettingsMatch() {
        var s = PointerSettings()
        s.mode = .linear
        s.speed = 0.3
        let resolution = PointerController.resolution(forSpeed: 0.3)
        XCTAssertTrue(PointerController.isApplied(s, current: Live(resolution: resolution, acceleration: 0.5, linear: 1), supportsLinear: true))
        XCTAssertFalse(PointerController.isApplied(s, current: Live(resolution: resolution, acceleration: 0.5, linear: 0), supportsLinear: true))
        XCTAssertTrue(PointerController.isApplied(s, current: Live(resolution: resolution, acceleration: -1, linear: nil), supportsLinear: false))
    }

    func testUnreadableValuesDoNotTriggerEndlessRepairs() {
        var s = PointerSettings()
        s.mode = .custom
        XCTAssertTrue(PointerController.isApplied(s, current: Live(resolution: nil, acceleration: nil, linear: nil), supportsLinear: false))
    }

    func testSystemModeIsNeverRepaired() {
        XCTAssertTrue(PointerController.isApplied(PointerSettings(), current: Live(resolution: 400, acceleration: 3, linear: 1), supportsLinear: true))
    }
}

final class SoleMouseTests: XCTestCase {
    func testKeyboardPointerInterfaceIsNotTheMouse() {
        let mouse = DeviceInfo(vendorID: 0x1234, productID: 0x5678, name: "Example Wireless Receiver", category: .mouse)
        let keyboard = DeviceInfo(vendorID: 0x1111, productID: 0x2222, name: "USB Keyboard", category: .mouse)
        let trackpad = DeviceInfo(vendorID: 0x5AC, productID: 0x281, name: "Apple Internal Keyboard / Trackpad", category: .trackpad)
        XCTAssertEqual([trackpad, keyboard, mouse].soleMouse, mouse)
        XCTAssertNil([mouse, DeviceInfo(vendorID: 1, productID: 2, name: "Other Mouse", category: .mouse)].soleMouse)
        XCTAssertNil([trackpad].soleMouse)
    }
}
