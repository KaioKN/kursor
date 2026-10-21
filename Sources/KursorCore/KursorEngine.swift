import AppKit
import ApplicationServices
import IOKit.hid

/// Public facade used by the app. Call from the main thread.
public final class KursorEngine {
    public static let shared = KursorEngine()

    public let diagnostics = Diagnostics()
    /// Delivered on the main thread.
    public var onDevicesChanged: (([DeviceInfo]) -> Void)?
    public var onActiveDeviceChanged: ((DeviceInfo) -> Void)?

    public private(set) var isRunning = false
    public private(set) var devices: [DeviceInfo] = []
    public private(set) var activeDevice: DeviceInfo?

    private let pointer = PointerController()
    private let focus = FocusFollower()
    private var thread: EventThread?
    private var pipeline: Pipeline?
    private var config = KursorConfig()
    private var workspaceObserver: NSObjectProtocol?
    private var wakeObservers: [NSObjectProtocol] = []
    private var watchdog: Timer?

    public init() {}

    // MARK: - Permissions

    public static var hasAccessibility: Bool { AXIsProcessTrusted() }

    public static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static var hasInputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    public static func requestInputMonitoring() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public static let linearMouseBundleID = "com.lujjjh.LinearMouse"

    public static var linearMouseRunning: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: linearMouseBundleID)
    }

    // MARK: - Lifecycle

    /// Returns false when the event tap cannot be created (no Accessibility permission).
    @discardableResult
    public func start(config: KursorConfig) -> Bool {
        self.config = config
        if isRunning {
            update(config: config)
            return true
        }

        let thread = EventThread()
        thread.startAndWait()
        let pipeline = Pipeline(thread: thread, pointer: pointer, diagnostics: diagnostics)
        let installed = thread.performAndWait { () -> Bool in
            pipeline.config = config
            pipeline.devices.onDevicesChanged = { [weak self] list in
                DispatchQueue.main.async { self?.devicesChanged(list) }
            }
            pipeline.devices.onActiveDeviceChanged = { [weak self] info in
                DispatchQueue.main.async {
                    self?.activeDevice = info
                    self?.onActiveDeviceChanged?(info)
                }
            }
            pipeline.devices.start(runLoop: thread.runLoop)
            let userInfo = Unmanaged.passUnretained(pipeline).toOpaque()
            return pipeline.tap.install(on: thread.runLoop, callback: kursorTapCallback, userInfo: userInfo)
        }
        guard installed else {
            thread.performAndWait { pipeline.devices.stop() }
            thread.stop()
            return false
        }

        self.thread = thread
        self.pipeline = pipeline
        isRunning = true
        trackFrontmostApp()
        pointer.apply(config)
        focus.update(Self.focusSettings(config))

        // macOS can silently disable a tap (e.g. after a slow callback) or reset pointer
        // properties (wake, reconnect); re-arm the tap and repair drifted settings.
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, let pipeline = self.pipeline, let thread = self.thread else { return }
            thread.perform {
                if !pipeline.tap.isEnabled { pipeline.tap.enable() }
                pipeline.publishCounters()
            }
            self.pointer.verify()
        }
        observeWake()
        return true
    }

    public func update(config: KursorConfig) {
        self.config = config
        guard let pipeline, let thread else { return }
        thread.perform { pipeline.config = config }
        pointer.apply(config)
        focus.update(Self.focusSettings(config))
    }

    private static func focusSettings(_ config: KursorConfig) -> FocusSettings {
        var settings = config.focus
        if !config.enabled { settings.mode = .off }
        return settings
    }

    public func stop() {
        focus.stop()
        wakeObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        wakeObservers.removeAll()
        watchdog?.invalidate()
        watchdog = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        if let pipeline, let thread {
            thread.performAndWait {
                pipeline.resetAll()
                pipeline.tap.remove()
                pipeline.devices.stop()
            }
            thread.stop()
        }
        pipeline = nil
        thread = nil
        isRunning = false
        pointer.restoreAll(wait: true)
    }

    /// Re-open the HID manager, e.g. after Input Monitoring was granted.
    public func restartDeviceMonitor() {
        guard let pipeline, let thread else { return }
        thread.perform { pipeline.devices.start(runLoop: thread.runLoop) }
    }

    public var inputMonitoringActive: Bool {
        guard let pipeline, let thread else { return false }
        return thread.performAndWait { pipeline.devices.inputOpen }
    }

    // MARK: - Lab (manual checks of synthetic gestures)

    /// Posts a short pinch-zoom gesture to whatever is under the cursor.
    public func testPinch(zoomIn: Bool = true) {
        DispatchQueue.global(qos: .userInteractive).async {
            EventSynth.magnify(0, phase: .began)
            for _ in 0..<20 {
                EventSynth.magnify(zoomIn ? 0.02 : -0.02, phase: .changed)
                usleep(8000)
            }
            EventSynth.magnify(0, phase: .ended)
        }
    }

    public func testSmartZoom() {
        EventSynth.smartZoom()
    }

    public func testSpaceSwitch(right: Bool) {
        DispatchQueue.global().async { EventSynth.symbolicHotKey(right ? .spaceRight : .spaceLeft) }
    }

    // MARK: - Private

    private func devicesChanged(_ list: [DeviceInfo]) {
        devices = list
        onDevicesChanged?(list)
        // New HID services appear slightly after the device; apply pointer settings once they exist.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.pointer.refresh()
        }
    }

    /// After sleep USB devices are often re-enumerated and HID properties reset: rebuild
    /// device state and re-apply settings (twice, as receivers can come back late).
    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            wakeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.recoverAfterWake()
            })
        }
    }

    private func recoverAfterWake() {
        guard let pipeline, let thread else { return }
        thread.perform {
            pipeline.tap.enable()
            pipeline.devices.start(runLoop: thread.runLoop)
        }
        for delay in [1.0, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pointer.refresh()
            }
        }
    }

    private func trackFrontmostApp() {
        let update: (NSRunningApplication?) -> Void = { [weak self] app in
            self?.pipeline?.frontmostApp.withLock { $0 = app?.bundleIdentifier }
        }
        update(NSWorkspace.shared.frontmostApplication)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            update(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }
}

private func kursorTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let pipeline = Unmanaged<Pipeline>.fromOpaque(refcon).takeUnretainedValue()
    guard let out = pipeline.handle(type: type, event: event) else { return nil }
    return Unmanaged.passUnretained(out)
}
