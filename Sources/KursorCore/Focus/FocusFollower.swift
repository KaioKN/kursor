import AppKit
import ApplicationServices
import KursorSPI

/// Activates the window under the cursor so the next click lands in it instead of only
/// focusing it. Triggers when the cursor comes to rest after moving to another display,
/// or (in `.always` mode) whenever it rests over a window. Runs on the main thread;
/// Accessibility calls into other apps go to a background queue so a hung app cannot
/// stall Kursor.
public final class FocusFollower {
    public struct WindowInfo: Equatable {
        public var windowID: CGWindowID
        public var pid: pid_t
        public var bounds: CGRect
        public var layer: Int
        public var alpha: Double
        public var owner: String

        public init(windowID: CGWindowID, pid: pid_t, bounds: CGRect, layer: Int = 0, alpha: Double = 1, owner: String = "") {
            self.windowID = windowID
            self.pid = pid
            self.bounds = bounds
            self.layer = layer
            self.alpha = alpha
            self.owner = owner
        }
    }

    private var settings = FocusSettings()
    private var timer: Timer?
    private let axQueue = DispatchQueue(label: "app.kursor.focus", qos: .userInitiated)
    private var lastLocation: CGPoint?
    private var lastMove: TimeInterval = 0
    private var lastDisplay: CGDirectDisplayID?
    /// A display change (or, in `.always` mode, any movement) waiting for the cursor to rest.
    private var pending = false
    private var busy = false

    // Mission Control / App Exposé / Show Desktop, reported by the Dock over Accessibility.
    private var dockObserver: AXObserver?
    private var dockPID: pid_t = 0
    private var exposeActive = false
    private var exposeSince: TimeInterval = 0

    public init() {}

    public func update(_ settings: FocusSettings) {
        self.settings = settings
        if settings.mode == .off { stop() } else { start() }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        pending = false
        removeDockObserver()
    }

    private func start() {
        guard timer == nil else { return }
        lastLocation = nil
        lastDisplay = nil
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        observeDock()
    }

    // MARK: - Polling

    private func poll() {
        guard let location = CGEvent(source: nil)?.location else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let display = Self.display(at: location)

        if location != lastLocation {
            lastLocation = location
            lastMove = now
            if settings.mode == .always { pending = true }
        }
        if display != lastDisplay {
            // The first sample after start is not a "change".
            if lastDisplay != nil, settings.mode == .displayChange { pending = true }
            lastDisplay = display
        }

        // A missed "exit" must not disable focusing forever.
        if exposeActive, now - exposeSince > 60 { exposeActive = false }

        // Never steal focus mid-drag (e.g. while moving a window between displays)
        // or while Mission Control shows window thumbnails.
        if Self.anyButtonDown || exposeActive {
            pending = false
            return
        }
        guard pending, !busy, now - lastMove >= settings.delayMs / 1000 else { return }
        pending = false
        focusWindow(at: location)
    }

    private func focusWindow(at point: CGPoint) {
        observeDock() // re-attach if the Dock was restarted
        let windows = Self.windowList()
        let screen = Self.display(at: point).map { CGDisplayBounds($0) }
        guard let target = Self.target(at: point, in: windows, screen: screen, visibleArea: Self.visibleArea(at: point)) else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard !Self.isFocused(target, in: windows, frontmostPID: frontmost) else { return }

        if target.pid == getpid() {
            // Our own windows: AX calls into ourselves from the main thread would deadlock.
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.windowNumber == Int(target.windowID) }?.makeKeyAndOrderFront(nil)
            return
        }

        busy = true
        axQueue.async { [weak self] in
            Self.focus(target)
            DispatchQueue.main.async { self?.busy = false }
        }
    }

    // MARK: - Window selection (pure, tested)

    /// The normal window directly under `point`, or nil when something that should keep
    /// focus where it is lies on top (menu bar, Dock, menus, popovers).
    /// `visibleArea` is the screen minus menu bar and Dock (NSScreen.visibleFrame).
    public static func target(at point: CGPoint, in windows: [WindowInfo], screen: CGRect?, visibleArea: CGRect?) -> WindowInfo? {
        if let visibleArea, !visibleArea.contains(point) { return nil }
        for w in windows where w.alpha > 0 && w.bounds.contains(point) {
            if w.layer == 0 {
                // Tiny layer-0 windows are tooltips and similar helpers.
                return w.bounds.width >= 40 && w.bounds.height >= 40 ? w : nil
            }
            // The Dock keeps a transparent full-screen window on its display; the Dock bar
            // itself is excluded via `visibleArea`, Mission Control via AX notifications.
            if w.owner == "Dock" { continue }
            // Other apps' full-screen overlays are usually click-through: look beneath.
            let coversScreen = screen.map { w.bounds.width >= $0.width * 0.9 && w.bounds.height >= $0.height * 0.9 } ?? false
            if coversScreen { continue }
            return nil
        }
        return nil
    }

    /// Already focused when it belongs to the frontmost app and is that app's topmost window.
    public static func isFocused(_ target: WindowInfo, in windows: [WindowInfo], frontmostPID: pid_t?) -> Bool {
        guard target.pid == frontmostPID else { return false }
        return windows.first { $0.pid == target.pid && $0.layer == 0 }?.windowID == target.windowID
    }

    // MARK: - Mission Control

    private static let exposeNotifications = [
        "AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit",
    ]

    private func observeDock() {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        guard dockObserver == nil || dock.processIdentifier != dockPID else { return }
        removeDockObserver()

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            Unmanaged<FocusFollower>.fromOpaque(refcon).takeUnretainedValue()
                .exposeChanged(active: (notification as String) != "AXExposeExit")
        }
        guard AXObserverCreate(dock.processIdentifier, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.exposeNotifications {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        dockObserver = observer
        dockPID = dock.processIdentifier
    }

    private func removeDockObserver() {
        if let dockObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(dockObserver), .commonModes)
        }
        dockObserver = nil
        dockPID = 0
        exposeActive = false
    }

    private func exposeChanged(active: Bool) {
        exposeActive = active
        exposeSince = ProcessInfo.processInfo.systemUptime
        pending = false
    }

    // MARK: - System access

    /// The screen's area without menu bar and Dock, in global CG coordinates (top-left origin).
    static func visibleArea(at point: CGPoint) -> CGRect? {
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return nil }
        func flip(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
        }
        return NSScreen.screens.first { flip($0.frame).contains(point) }.map { flip($0.visibleFrame) }
    }

    static var anyButtonDown: Bool {
        [CGMouseButton.left, .right, .center].contains {
            CGEventSource.buttonState(.combinedSessionState, button: $0)
        }
    }

    static func display(at point: CGPoint) -> CGDirectDisplayID? {
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &id, &count) == .success, count > 0 else { return nil }
        return id
    }

    /// On-screen windows, front to back.
    static func windowList() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { d in
            guard let id = (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsDict = d[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return WindowInfo(
                windowID: id,
                pid: pid,
                bounds: bounds,
                layer: (d[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                alpha: (d[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                owner: d[kCGWindowOwnerName as String] as? String ?? ""
            )
        }
    }

    /// Raises the window, makes it main and its app frontmost (via Accessibility, which is
    /// not subject to the cooperative app-activation rules that NSRunningApplication is).
    static func focus(_ target: WindowInfo) {
        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, 0.3)

        if let window = axWindow(of: app, matching: target) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        if AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue) != .success {
            NSRunningApplication(processIdentifier: target.pid)?.activate()
        }
    }

    private static func axWindow(of app: AXUIElement, matching target: WindowInfo) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return nil }

        for window in windows {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(window, &id) == .success, id == target.windowID { return window }
        }
        // Fallback when the private lookup fails: match by frame.
        return windows.first { frame(of: $0).map { $0.integral == target.bounds.integral } ?? false }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
