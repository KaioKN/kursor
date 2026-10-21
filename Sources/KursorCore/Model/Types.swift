import CoreGraphics
import Foundation

/// CGEvent button number: 0 left, 1 right, 2 middle, 3+ side buttons.
public typealias ButtonNumber = Int

public enum DeviceCategory: String, Codable, Sendable {
    case mouse
    case trackpad
}

public struct DeviceInfo: Hashable, Sendable, Identifiable {
    public var vendorID: Int
    public var productID: Int
    public var name: String
    public var category: DeviceCategory
    public var transport: String

    public var id: String { "\(vendorID):\(productID):\(name)" }

    public init(vendorID: Int, productID: Int, name: String, category: DeviceCategory, transport: String = "") {
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.category = category
        self.transport = transport
    }

    /// Apple's built-in and Magic trackpads report as pointers, so the name is the most reliable signal.
    public static func guessCategory(name: String, vendorID: Int) -> DeviceCategory {
        name.localizedCaseInsensitiveContains("trackpad") ? .trackpad : .mouse
    }
}

public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let control = Modifiers(rawValue: 1 << 2)
    public static let shift = Modifiers(rawValue: 1 << 3)

    public init(_ flags: CGEventFlags) {
        var m: Modifiers = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        self = m
    }

    public var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if contains(.command) { f.insert(.maskCommand) }
        if contains(.option) { f.insert(.maskAlternate) }
        if contains(.control) { f.insert(.maskControl) }
        if contains(.shift) { f.insert(.maskShift) }
        return f
    }

    public var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

public extension Array where Element == DeviceInfo {
    /// The only real mouse among connected devices, used when the active one is unknown
    /// (no Input Monitoring yet). Keyboards often expose a pointer interface for media
    /// keys, so they do not count.
    var soleMouse: DeviceInfo? {
        let mice = filter { $0.category == .mouse }
        if mice.count == 1 { return mice[0] }
        let real = mice.filter { !$0.name.localizedCaseInsensitiveContains("keyboard") }
        return real.count == 1 ? real[0] : nil
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        hypot(Double(x - other.x), Double(y - other.y))
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
        CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }

    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }
}

extension CGVector {
    var length: Double { hypot(Double(dx), Double(dy)) }
}
