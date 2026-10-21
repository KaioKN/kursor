import Foundation

/// Imports per-device settings from LinearMouse's `~/.config/linearmouse/linearmouse.json`.
/// LinearMouse's schema is loose (numbers or {vertical, horizontal} objects, hex-string IDs),
/// so it is read with JSONSerialization rather than Codable.
public enum LinearMouseImporter {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/linearmouse/linearmouse.json")
    }

    public struct Result: Equatable {
        public var config: KursorConfig
        public var importedDevices: [String]
        public var skippedSchemes: Int
    }

    public enum ImportError: Error {
        case unreadable
        case noSchemes
    }

    public static func importConfig(from url: URL = defaultURL, into base: KursorConfig) throws -> Result {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        return try importConfig(data: data, into: base)
    }

    public static func importConfig(data: Data, into base: KursorConfig) throws -> Result {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schemes = root["schemes"] as? [[String: Any]], !schemes.isEmpty
        else { throw ImportError.noSchemes }

        var config = base
        var imported: [String] = []
        var skipped = 0

        for scheme in schemes {
            guard let device = deviceCondition(scheme["if"]),
                  let vendorID = intValue(device["vendorID"]),
                  let productID = intValue(device["productID"])
            else {
                skipped += 1
                continue
            }
            let name = (device["productName"] as? String) ?? String(format: "%04X:%04X", vendorID, productID)
            let isTrackpad = (device["category"] as? String) == "trackpad"

            let index: Int
            if isTrackpad, let i = config.profiles.firstIndex(where: { $0.match?.category == .trackpad && $0.match?.vendorID == nil }) {
                index = i
            } else if let i = config.profiles.firstIndex(where: { $0.match?.vendorID == vendorID && $0.match?.productID == productID }) {
                index = i
            } else {
                var profile = isTrackpad ? DeviceProfile.defaultTrackpad() : config.profile(for: nil)
                profile.id = UUID().uuidString
                profile.name = name
                profile.match = DeviceMatch(vendorID: vendorID, productID: productID, name: name)
                config.profiles.append(profile)
                index = config.profiles.count - 1
            }

            apply(scheme: scheme, to: &config.profiles[index], isTrackpad: isTrackpad)
            imported.append(name)
        }

        return Result(config: config, importedDevices: imported, skippedSchemes: skipped)
    }

    // MARK: - Mapping

    static func apply(scheme: [String: Any], to profile: inout DeviceProfile, isTrackpad: Bool) {
        if !isTrackpad, let pointer = scheme["pointer"] as? [String: Any] {
            let speed = doubleValue(pointer["speed"])
            let acceleration = doubleValue(pointer["acceleration"])
            // Later schemes override earlier ones field by field (LinearMouse merge semantics),
            // so an absent `disableAcceleration` keeps whatever an earlier scheme set.
            switch pointer["disableAcceleration"] as? Bool {
            case true?: profile.pointer.mode = .linear
            case false?: profile.pointer.mode = .custom
            case nil:
                if profile.pointer.mode == .system, speed != nil || acceleration != nil {
                    profile.pointer.mode = .custom
                }
            }
            if let speed { profile.pointer.speed = min(max(speed, 0), 1) }
            if let acceleration { profile.pointer.acceleration = max(acceleration, 0) }
        }

        if let scrolling = scheme["scrolling"] as? [String: Any] {
            if let reverse = axisPair(scrolling["reverse"], as: Bool.self) {
                if let v = reverse.0 { profile.scroll.reverseVertical = v }
                if let h = reverse.1 { profile.scroll.reverseHorizontal = h }
            }
            // LinearMouse's speed is an abstract multiplier; ~8 px per unit feels equivalent.
            if !isTrackpad, let speed = axisPair(scrolling["speed"], as: Double.self), let v = speed.0, v > 0 {
                profile.scroll.speed = min(max(v * 8, 15), 160)
            }
        }

        if let buttons = scheme["buttons"] as? [String: Any],
           let mappings = buttons["mappings"] as? [[String: Any]] {
            for m in mappings {
                let hasModifiers = ["command", "shift", "option", "control"].contains { (m[$0] as? Bool) == true }
                guard !hasModifiers,
                      let button = intValue(m["button"]),
                      let action = (m["action"] as? String).flatMap(mapAction)
                else { continue }
                profile.buttons.setAction(action, for: button)
            }
        }
    }

    static func mapAction(_ lm: String) -> ButtonAction? {
        switch lm {
        case "missionControl.spaceLeft": return .spaceLeft
        case "missionControl.spaceRight": return .spaceRight
        case "missionControl": return .missionControl
        case "missionControl.applicationWindows", "appExpose": return .appExpose
        case "missionControl.showDesktop", "showDesktop": return .showDesktop
        case "launchpad": return .launchpad
        case "mouse.button.back": return .back
        case "mouse.button.forward": return .forward
        case "mouse.button.middle": return .middleClick
        default: return nil
        }
    }

    // MARK: - Loose JSON helpers

    /// `if` may be a single condition object or an array of them.
    static func deviceCondition(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict["device"] as? [String: Any] }
        if let list = value as? [[String: Any]] {
            return list.lazy.compactMap { $0["device"] as? [String: Any] }.first
        }
        return nil
    }

    /// LinearMouse writes either a scalar (both axes) or {vertical, horizontal}.
    static func axisPair<T>(_ value: Any?, as: T.Type) -> (T?, T?)? {
        if let scalar = value as? T { return (scalar, scalar) }
        if let dict = value as? [String: Any] {
            return (dict["vertical"] as? T, dict["horizontal"] as? T)
        }
        return nil
    }

    static func intValue(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let s = value as? String {
            let t = s.lowercased()
            return t.hasPrefix("0x") ? Int(t.dropFirst(2), radix: 16) : Int(t)
        }
        return nil
    }

    static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
