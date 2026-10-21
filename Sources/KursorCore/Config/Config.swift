import Foundation

// All config structs decode tolerantly: a missing or malformed key falls back to its
// default instead of failing the whole file, so adding settings never wipes a config.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        if let v = try? decodeIfPresent(T.self, forKey: key) { return v }
        return fallback()
    }
}

public enum PointerMode: String, Codable, CaseIterable, Sendable {
    /// Leave macOS settings untouched.
    case system
    /// Own speed + macOS acceleration curve with a custom amount.
    case custom
    /// Own speed, acceleration off (1:1 movement).
    case linear
}

public enum MiddleButtonMode: String, Codable, CaseIterable, Sendable {
    case normal
    /// Hold and drag to scroll the document; a click without movement stays a middle click.
    case pan
    /// Windows-style: middle click toggles autoscroll, cursor offset sets the speed.
    case autoscroll
}

public enum ButtonAction: String, Codable, CaseIterable, Sendable {
    case none
    case back
    case forward
    case spaceLeft
    case spaceRight
    case missionControl
    case appExpose
    case showDesktop
    case launchpad
    case smartZoom
    case precision
    case nextDisplay
    case gesture
    case middleClick

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ButtonAction(rawValue: raw) ?? .none
    }

    /// Actions that can be bound to a gesture direction (no nested hold actions).
    public static let directional: [ButtonAction] = [
        .none, .spaceLeft, .spaceRight, .missionControl, .appExpose, .showDesktop,
        .launchpad, .back, .forward, .smartZoom, .nextDisplay,
    ]
}

public struct ButtonMapping: Codable, Equatable, Hashable, Sendable {
    public var button: ButtonNumber
    public var action: ButtonAction

    public init(button: ButtonNumber, action: ButtonAction) {
        self.button = button
        self.action = action
    }
}

public struct GestureSettings: Codable, Equatable, Sendable {
    /// Movement (px) before a direction is recognized.
    public var threshold: Double = 60
    public var left: ButtonAction = .spaceLeft
    public var right: ButtonAction = .spaceRight
    public var up: ButtonAction = .missionControl
    public var down: ButtonAction = .appExpose
    /// What a click (press without movement) of the gesture button does.
    public var click: ButtonAction = .none

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GestureSettings()
        threshold = c.value(.threshold, d.threshold)
        left = c.value(.left, d.left)
        right = c.value(.right, d.right)
        up = c.value(.up, d.up)
        down = c.value(.down, d.down)
        click = c.value(.click, d.click)
    }
}

public struct ClickSettings: Codable, Equatable, Sendable {
    /// Swallow tiny movement between press and release so a click never turns into a drag.
    public var stabilize: Bool = true
    /// Movement (px) tolerated while the button is down.
    public var radius: Double = 4
    /// Time window (ms) during which movement is tolerated; after it, dragging works as usual.
    public var maxDurationMs: Double = 200
    public var buttons: [ButtonNumber] = [0, 1]
    /// Additionally pin the visible cursor during the window (experimental).
    public var freezeCursor: Bool = false
    public var debounce: Bool = false
    public var debounceMs: Double = 30
    /// Release a button macOS thinks is held when the hardware says it is up.
    public var stuckGuard: Bool = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClickSettings()
        stabilize = c.value(.stabilize, d.stabilize)
        radius = c.value(.radius, d.radius)
        maxDurationMs = c.value(.maxDurationMs, d.maxDurationMs)
        buttons = c.value(.buttons, d.buttons)
        freezeCursor = c.value(.freezeCursor, d.freezeCursor)
        debounce = c.value(.debounce, d.debounce)
        debounceMs = c.value(.debounceMs, d.debounceMs)
        stuckGuard = c.value(.stuckGuard, d.stuckGuard)
    }
}

public struct PointerSettings: Codable, Equatable, Sendable {
    public var mode: PointerMode = .system
    /// 0...1, same scale as LinearMouse (maps to HIDPointerResolution 1200...40).
    public var speed: Double = 0.5
    /// macOS acceleration amount used in `.custom` mode (system default ≈ 0.6875).
    public var acceleration: Double = 0.6875
    /// Cursor slowdown while the precision button is held.
    public var precisionFactor: Double = 3.5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PointerSettings()
        mode = c.value(.mode, d.mode)
        speed = c.value(.speed, d.speed)
        acceleration = c.value(.acceleration, d.acceleration)
        precisionFactor = c.value(.precisionFactor, d.precisionFactor)
    }
}

public struct ScrollSettings: Codable, Equatable, Sendable {
    public var smooth: Bool = true
    /// Pixels per wheel line.
    public var speed: Double = 40
    /// Extra distance when spinning the wheel fast, 0 = none.
    public var acceleration: Double = 0.6
    /// Glide time constant (ms): higher = longer, softer stop.
    public var inertiaMs: Double = 110
    public var reverseVertical: Bool = false
    public var reverseHorizontal: Bool = false
    public var middleButton: MiddleButtonMode = .pan
    public var panSpeed: Double = 1.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScrollSettings()
        smooth = c.value(.smooth, d.smooth)
        speed = c.value(.speed, d.speed)
        acceleration = c.value(.acceleration, d.acceleration)
        inertiaMs = c.value(.inertiaMs, d.inertiaMs)
        reverseVertical = c.value(.reverseVertical, d.reverseVertical)
        reverseHorizontal = c.value(.reverseHorizontal, d.reverseHorizontal)
        middleButton = c.value(.middleButton, d.middleButton)
        panSpeed = c.value(.panSpeed, d.panSpeed)
    }
}

public struct ButtonSettings: Codable, Equatable, Sendable {
    public var mappings: [ButtonMapping] = []
    public var gesture = GestureSettings()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mappings = c.value(.mappings, [])
        gesture = c.value(.gesture, GestureSettings())
    }

    public func action(for button: ButtonNumber) -> ButtonAction {
        mappings.last(where: { $0.button == button })?.action ?? .none
    }

    public mutating func setAction(_ action: ButtonAction, for button: ButtonNumber) {
        mappings.removeAll { $0.button == button }
        if action != .none { mappings.append(ButtonMapping(button: button, action: action)) }
        mappings.sort { $0.button < $1.button }
    }
}

public struct DeviceMatch: Codable, Equatable, Hashable, Sendable {
    public var vendorID: Int?
    public var productID: Int?
    public var category: DeviceCategory?
    /// Informational only (shown in UI), not used for matching.
    public var name: String?

    public init(vendorID: Int? = nil, productID: Int? = nil, category: DeviceCategory? = nil, name: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.category = category
        self.name = name
    }

    /// 0 = no match, higher = more specific.
    public func score(_ device: DeviceInfo) -> Int {
        if let vendorID, let productID {
            return vendorID == device.vendorID && productID == device.productID ? 2 : 0
        }
        if let category { return category == device.category ? 1 : 0 }
        return 0
    }
}

public struct DeviceProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// nil = the default profile used when nothing more specific matches.
    public var match: DeviceMatch?
    public var click = ClickSettings()
    public var pointer = PointerSettings()
    public var scroll = ScrollSettings()
    public var buttons = ButtonSettings()

    public init(id: String = UUID().uuidString, name: String, match: DeviceMatch?) {
        self.id = id
        self.name = name
        self.match = match
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID().uuidString)
        name = c.value(.name, "Профиль")
        match = (try? c.decodeIfPresent(DeviceMatch.self, forKey: .match)) ?? nil
        click = c.value(.click, ClickSettings())
        pointer = c.value(.pointer, PointerSettings())
        scroll = c.value(.scroll, ScrollSettings())
        buttons = c.value(.buttons, ButtonSettings())
    }

    public static func defaultMouse() -> DeviceProfile {
        DeviceProfile(id: "default", name: "Все мыши (по умолчанию)", match: nil)
    }

    public static func defaultTrackpad() -> DeviceProfile {
        var p = DeviceProfile(id: "trackpad", name: "Трекпад", match: DeviceMatch(category: .trackpad))
        p.click.stabilize = false
        p.click.stuckGuard = false
        p.scroll.smooth = false
        p.scroll.middleButton = .normal
        return p
    }
}

public struct ZoomSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    public var modifiers: Modifiers = [.command]
    /// Multiplier for magnification per wheel line.
    public var sensitivity: Double = 1.0
    public var invert: Bool = false
    /// Apps that ignore pinch events get ⌘= / ⌘− instead.
    public var keyFallbackApps: [String] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.Zed",
        "com.jetbrains.intellij",
    ]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ZoomSettings()
        enabled = c.value(.enabled, d.enabled)
        modifiers = c.value(.modifiers, d.modifiers)
        sensitivity = c.value(.sensitivity, d.sensitivity)
        invert = c.value(.invert, d.invert)
        keyFallbackApps = c.value(.keyFallbackApps, d.keyFallbackApps)
    }
}

public struct RotateSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    public var modifiers: Modifiers = [.command, .option]
    /// Degrees per wheel line.
    public var degreesPerLine: Double = 4

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RotateSettings()
        enabled = c.value(.enabled, d.enabled)
        modifiers = c.value(.modifiers, d.modifiers)
        degreesPerLine = c.value(.degreesPerLine, d.degreesPerLine)
    }
}

public enum FocusMode: String, Codable, CaseIterable, Sendable {
    case off
    /// Activate the window under the cursor when the cursor moves to another display.
    case displayChange
    /// Focus follows the mouse everywhere (after the cursor rests over a window).
    case always
}

public struct FocusSettings: Codable, Equatable, Sendable {
    public var mode: FocusMode = .displayChange
    /// How long the cursor must rest before focusing (ms).
    public var delayMs: Double = 120

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FocusSettings()
        mode = c.value(.mode, d.mode)
        delayMs = c.value(.delayMs, d.delayMs)
    }
}

public struct KursorConfig: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var enabled: Bool = true
    public var profiles: [DeviceProfile] = [.defaultMouse(), .defaultTrackpad()]
    public var zoom = ZoomSettings()
    public var rotate = RotateSettings()
    public var focus = FocusSettings()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KursorConfig()
        version = c.value(.version, d.version)
        enabled = c.value(.enabled, d.enabled)
        profiles = c.value(.profiles, d.profiles)
        zoom = c.value(.zoom, d.zoom)
        rotate = c.value(.rotate, d.rotate)
        focus = c.value(.focus, d.focus)
        if !profiles.contains(where: { $0.match == nil }) {
            profiles.insert(.defaultMouse(), at: 0)
        }
    }

    /// The most specific profile for a device; falls back to the default (match == nil) profile.
    public func profile(for device: DeviceInfo?) -> DeviceProfile {
        let fallback = profiles.first(where: { $0.match == nil }) ?? .defaultMouse()
        guard let device else { return fallback }
        var best: (score: Int, profile: DeviceProfile)?
        for p in profiles {
            guard let match = p.match else { continue }
            let s = match.score(device)
            if s > 0, s > (best?.score ?? 0) { best = (s, p) }
        }
        return best?.profile ?? fallback
    }
}
