import Foundation
import IOKit.hid

/// Enumerates pointing devices and remembers which one produced the latest input report,
/// so each CGEvent can be attributed to a device profile. Runs on the event thread.
final class DeviceMonitor {
    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private var infos: [UnsafeMutableRawPointer: DeviceInfo] = [:]
    private var lastActiveKey: UnsafeMutableRawPointer?
    private(set) var lastActive: DeviceInfo?
    /// False when Input Monitoring is not granted: devices are listed, activity is not seen.
    private(set) var inputOpen = false

    /// Called on the event thread.
    var onDevicesChanged: (([DeviceInfo]) -> Void)?
    var onActiveDeviceChanged: ((DeviceInfo) -> Void)?

    var connected: [DeviceInfo] {
        var seen = Set<String>()
        return infos.values
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name < $1.name }
    }

    /// Best guess when no input was observed yet: the only connected mouse.
    var activeOrSoleMouse: DeviceInfo? {
        lastActive ?? connected.soleMouse
    }

    func start(runLoop: CFRunLoop) {
        stop()
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(m, matching as CFArray)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<DeviceMonitor>.fromOpaque(ctx).takeUnretainedValue().added(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<DeviceMonitor>.fromOpaque(ctx).takeUnretainedValue().removed(device)
        }, ctx)
        IOHIDManagerRegisterInputReportCallback(m, { ctx, _, sender, _, _, _, _ in
            guard let ctx, let sender else { return }
            Unmanaged<DeviceMonitor>.fromOpaque(ctx).takeUnretainedValue().activity(sender)
        }, ctx)

        IOHIDManagerScheduleWithRunLoop(m, runLoop, CFRunLoopMode.defaultMode.rawValue)
        self.runLoop = runLoop
        inputOpen = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
        manager = m
    }

    func stop() {
        guard let m = manager else { return }
        if let runLoop { IOHIDManagerUnscheduleFromRunLoop(m, runLoop, CFRunLoopMode.defaultMode.rawValue) }
        IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        infos.removeAll()
        lastActive = nil
        lastActiveKey = nil
    }

    // MARK: - Callbacks

    private func added(_ device: IOHIDDevice) {
        let key = Unmanaged.passUnretained(device).toOpaque()
        infos[key] = Self.info(for: device)
        onDevicesChanged?(connected)
    }

    private func removed(_ device: IOHIDDevice) {
        let key = Unmanaged.passUnretained(device).toOpaque()
        infos[key] = nil
        if lastActiveKey == key {
            lastActiveKey = nil
            lastActive = nil
        }
        onDevicesChanged?(connected)
    }

    /// Hot path (every input report, up to several kHz): pointer compare only.
    private func activity(_ sender: UnsafeMutableRawPointer) {
        guard sender != lastActiveKey, let info = infos[sender] else { return }
        lastActiveKey = sender
        if info != lastActive {
            lastActive = info
            onActiveDeviceChanged?(info)
        }
    }

    static func info(for device: IOHIDDevice) -> DeviceInfo {
        func prop(_ key: String) -> Any? { IOHIDDeviceGetProperty(device, key as CFString) }
        let vendor = (prop(kIOHIDVendorIDKey) as? NSNumber)?.intValue ?? 0
        let product = (prop(kIOHIDProductIDKey) as? NSNumber)?.intValue ?? 0
        let name = (prop(kIOHIDProductKey) as? String) ?? String(format: "Устройство %04X:%04X", vendor, product)
        let transport = (prop(kIOHIDTransportKey) as? String) ?? ""
        return DeviceInfo(
            vendorID: vendor,
            productID: product,
            name: name,
            category: DeviceInfo.guessCategory(name: name, vendorID: vendor),
            transport: transport
        )
    }
}
