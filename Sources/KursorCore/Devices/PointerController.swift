import Foundation
import IOKit.hid
import KursorSPI

/// Pointer speed/acceleration through HID service properties (no event rewriting),
/// the same mechanism LinearMouse uses. Original values are backed up to disk before
/// the first change so they can be restored after quitting or a crash.
final class PointerController {
    enum Key {
        static let resolution = "HIDPointerResolution"
        static let accelerationType = "HIDPointerAccelerationType"
        static let mouseAcceleration = "HIDMouseAcceleration"
        static let linearScaling = "HIDUseLinearScalingMouseAcceleration"
    }

    struct Originals: Codable, Equatable {
        var resolution: Double?
        var acceleration: Double?
        var accelerationKey: String
        var linear: Int?
    }

    private let queue = DispatchQueue(label: "app.kursor.pointer", qos: .userInitiated)
    /// An unscheduled client keeps the service list it was created with, so it is
    /// recreated whenever devices come and go (USB re-enumeration after sleep, replug).
    private var client: IOHIDEventSystemClient?
    private let backupURL: URL
    private var originals: [String: Originals]
    private var precisionSaved: [UInt64: Double] = [:]
    private var config: KursorConfig?
    public private(set) var repairs = 0

    init(backupURL: URL = ConfigStore.supportDirectory.appendingPathComponent("pointer-originals.json")) {
        client = Self.makeClient()
        self.backupURL = backupURL
        originals = (try? Data(contentsOf: backupURL)).flatMap { try? JSONDecoder().decode([String: Originals].self, from: $0) } ?? [:]
    }

    private static func makeClient() -> IOHIDEventSystemClient? {
        IOHIDEventSystemClientCreate(kCFAllocatorDefault) ?? IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    }

    // MARK: - Public (thread-safe, async)

    func apply(_ config: KursorConfig) {
        queue.async {
            self.config = config
            self.applyNow(config)
        }
    }

    /// Re-reads the device list and re-applies the last config (after device changes or wake).
    func refresh() {
        queue.async {
            self.client = Self.makeClient()
            if let config = self.config { self.applyNow(config) }
        }
    }

    /// Re-applies settings to any mouse whose live values drifted (macOS can reset them on
    /// wake or when a device reconnects).
    func verify() {
        queue.async {
            guard let config = self.config, config.enabled else { return }
            var drifted = false
            for (service, info) in self.services() {
                let settings = config.profile(for: info).pointer
                guard settings.mode != .system,
                      let id = Self.registryID(service), self.precisionSaved[id] == nil
                else { continue }
                if !Self.isApplied(settings, current: Self.current(service), supportsLinear: Self.readInt(service, Key.linearScaling) != nil) {
                    drifted = true
                }
            }
            guard drifted else { return }
            // A drifted value often means a re-enumerated device: start from a fresh service list.
            self.client = Self.makeClient()
            self.applyNow(config)
            self.repairs += 1
        }
    }

    func restoreAll(wait: Bool = false) {
        let work = { self.restoreNow() }
        if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    /// Temporarily slows the cursor of `device` (all mice when nil).
    func setPrecision(_ active: Bool, device: DeviceInfo?, factor: Double) {
        queue.async {
            for (service, info) in self.services() where Self.matches(info, device) {
                guard let id = Self.registryID(service) else { continue }
                if active {
                    guard self.precisionSaved[id] == nil else { continue }
                    let current = Self.readFixed(service, Key.resolution) ?? 400
                    self.precisionSaved[id] = current
                    Self.writeFixed(service, Key.resolution, min(current * max(factor, 1), 1995))
                } else if let saved = self.precisionSaved.removeValue(forKey: id) {
                    Self.writeFixed(service, Key.resolution, saved)
                }
            }
        }
    }

    // MARK: - Speed mapping (LinearMouse-compatible)

    static let speedRange = (1.0 / 1200)...(1.0 / 40)

    static func resolution(forSpeed speed: Double) -> Double {
        let s = min(max(speed, 0), 1)
        return 1 / (speedRange.lowerBound + s * (speedRange.upperBound - speedRange.lowerBound))
    }

    struct LiveValues: Equatable {
        var resolution: Double?
        var acceleration: Double?
        var linear: Int?
    }

    static func current(_ service: IOHIDServiceClient) -> LiveValues {
        LiveValues(
            resolution: readFixed(service, Key.resolution),
            acceleration: readFixed(service, accelerationKey(service)),
            linear: readInt(service, Key.linearScaling)
        )
    }

    /// Whether the live HID values already match `settings` (pure, tested).
    static func isApplied(_ settings: PointerSettings, current: LiveValues, supportsLinear: Bool) -> Bool {
        // An unreadable value cannot be verified; treat it as fine rather than re-applying forever.
        func near(_ a: Double?, _ b: Double, _ tolerance: Double) -> Bool {
            guard let a else { return true }
            return abs(a - b) <= tolerance
        }
        let resolutionOK = near(current.resolution, resolution(forSpeed: settings.speed), 0.5)
        switch settings.mode {
        case .system:
            return true
        case .linear:
            let linearOK = supportsLinear ? current.linear == 1 : near(current.acceleration, -1, 0.01)
            return resolutionOK && linearOK
        case .custom:
            let linearOK = !supportsLinear || current.linear == 0
            return resolutionOK && linearOK && near(current.acceleration, max(settings.acceleration, 0), 0.01)
        }
    }

    // MARK: - Implementation (on queue)

    private func applyNow(_ config: KursorConfig) {
        for (service, info) in services() {
            let settings = config.enabled ? config.profile(for: info).pointer : PointerSettings()
            let key = Self.deviceKey(info)
            switch settings.mode {
            case .system:
                if let o = originals[key] { restore(service, o) }
            case .custom, .linear:
                capture(service, key)
                let supportsLinear = Self.readInt(service, Key.linearScaling) != nil
                let accelKey = Self.accelerationKey(service)
                if settings.mode == .linear {
                    if supportsLinear {
                        Self.writeInt(service, Key.linearScaling, 1)
                    } else {
                        Self.writeFixed(service, accelKey, -1)
                    }
                    Self.writeFixed(service, Key.resolution, Self.resolution(forSpeed: settings.speed))
                } else {
                    if supportsLinear { Self.writeInt(service, Key.linearScaling, 0) }
                    Self.writeFixed(service, Key.resolution, Self.resolution(forSpeed: settings.speed))
                    Self.writeFixed(service, accelKey, max(settings.acceleration, 0))
                }
            }
        }
        saveOriginals()
    }

    private func restoreNow() {
        precisionSaved.removeAll()
        for (service, info) in services() {
            if let o = originals[Self.deviceKey(info)] { restore(service, o) }
        }
        originals.removeAll()
        try? FileManager.default.removeItem(at: backupURL)
    }

    private func capture(_ service: IOHIDServiceClient, _ key: String) {
        guard originals[key] == nil else { return }
        let accelKey = Self.accelerationKey(service)
        originals[key] = Originals(
            resolution: Self.readFixed(service, Key.resolution),
            acceleration: Self.readFixed(service, accelKey),
            accelerationKey: accelKey,
            linear: Self.readInt(service, Key.linearScaling)
        )
    }

    private func restore(_ service: IOHIDServiceClient, _ o: Originals) {
        if let linear = o.linear { Self.writeInt(service, Key.linearScaling, linear) }
        if let r = o.resolution { Self.writeFixed(service, Key.resolution, r) }
        if let a = o.acceleration { Self.writeFixed(service, o.accelerationKey, a) }
    }

    private func saveOriginals() {
        guard !originals.isEmpty else { return }
        try? FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(originals) {
            try? data.write(to: backupURL, options: .atomic)
        }
    }

    // MARK: - HID helpers

    private func services() -> [(IOHIDServiceClient, DeviceInfo)] {
        guard let client,
              let all = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]
        else { return [] }
        return all.compactMap { service in
            let isPointer = IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) != 0
                || IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Pointer)) != 0
            guard isPointer else { return nil }
            let vendor = (IOHIDServiceClientCopyProperty(service, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let product = (IOHIDServiceClientCopyProperty(service, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let name = (IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String) ?? ""
            let info = DeviceInfo(vendorID: vendor, productID: product, name: name,
                                  category: DeviceInfo.guessCategory(name: name, vendorID: vendor))
            return (service, info)
        }
    }

    static func matches(_ info: DeviceInfo, _ device: DeviceInfo?) -> Bool {
        guard let device else { return info.category == .mouse }
        return info.vendorID == device.vendorID && info.productID == device.productID
    }

    static func deviceKey(_ info: DeviceInfo) -> String {
        "\(info.vendorID):\(info.productID)"
    }

    static func registryID(_ service: IOHIDServiceClient) -> UInt64? {
        (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value
    }

    static func accelerationKey(_ service: IOHIDServiceClient) -> String {
        (IOHIDServiceClientCopyProperty(service, Key.accelerationType as CFString) as? String) ?? Key.mouseAcceleration
    }

    static func readFixed(_ service: IOHIDServiceClient, _ key: String) -> Double? {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber).map { $0.doubleValue / 65536 }
    }

    static func writeFixed(_ service: IOHIDServiceClient, _ key: String, _ value: Double) {
        let fixed = Int32(clamping: Int64((value * 65536).rounded()))
        _ = IOHIDServiceClientSetProperty(service, key as CFString, NSNumber(value: fixed))
    }

    static func readInt(_ service: IOHIDServiceClient, _ key: String) -> Int? {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.intValue
    }

    static func writeInt(_ service: IOHIDServiceClient, _ key: String, _ value: Int) {
        _ = IOHIDServiceClientSetProperty(service, key as CFString, NSNumber(value: value))
    }
}
