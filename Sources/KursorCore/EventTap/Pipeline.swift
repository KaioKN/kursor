import AppKit
import CoreGraphics
import Foundation
import os

/// Per-event processing. Everything here runs on the event thread; the tap callback
/// must stay fast (no logging, no I/O, no main-thread hops). Slow side effects
/// (keystrokes, Dock notifications, HID property writes) go to background queues.
final class Pipeline {
    let tap = EventTap()
    let devices = DeviceMonitor()
    let pointer: PointerController
    let diagnostics: Diagnostics
    private let thread: EventThread
    private let actions = DispatchQueue(label: "app.kursor.actions", qos: .userInteractive)

    var config = KursorConfig() {
        didSet { profileCache.removeAll() }
    }

    /// Bundle id of the frontmost app, written from the main thread.
    let frontmostApp = OSAllocatedUnfairLock<String?>(initialState: nil)

    // Features
    let stabilizer = ClickStabilizer()
    let debouncer = Debouncer()
    let stuckGuard = StuckButtonGuard()
    let middle = MiddleButtonScroll()
    let gesture = GestureButton()
    let zoom = GestureSmoother()
    let rotation = GestureSmoother()
    let scroller = SmoothScroller()
    let freeze = PointerFreeze()

    // State
    private var profileCache: [String: DeviceProfile] = [:]
    private var profile = DeviceProfile.defaultMouse()
    private var device: DeviceInfo?
    /// Buttons whose press was consumed by an action; their drags/release are consumed too.
    private var consumed: Set<ButtonNumber> = []
    private var precisionButton: ButtonNumber?
    private var freezeOwner: FreezeOwner?
    private var scrollFlags: CGEventFlags = []
    private var autoscrollCarry = CGVector.zero
    private var lastFrame: TimeInterval = 0
    private var counters = Diagnostics.Counters()

    private enum FreezeOwner { case stabilizer, gesture, pan }

    private lazy var frameTimer = RunLoopTimer(runLoop: thread.runLoop, interval: 1.0 / 120) { [unowned self] in self.frame() }
    private lazy var maintenanceTimer = RunLoopTimer(runLoop: thread.runLoop, interval: 0.25) { [unowned self] in self.maintenance() }

    init(thread: EventThread, pointer: PointerController, diagnostics: Diagnostics) {
        self.thread = thread
        self.pointer = pointer
        self.diagnostics = diagnostics
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - Entry point

    func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            tap.enable()
            counters.tapReenabled += 1
            recoverAfterTapLoss()
            return event
        default:
            break
        }
        if EventSynth.isSynthetic(event) || !config.enabled { return event }
        counters.events &+= 1
        resolveProfile(type: type, event: event)

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return mouseDown(event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return mouseUp(event)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return mouseDragged(event)
        case .scrollWheel:
            return scrollWheel(event)
        default:
            return event
        }
    }

    // MARK: - Device → profile

    private static let trackpadDevice = DeviceInfo(vendorID: 0, productID: 0, name: "Трекпад", category: .trackpad)

    private func resolveProfile(type: CGEventType, event: CGEvent) {
        var d = devices.activeOrSoleMouse
        // Continuous scroll comes from a trackpad (or Magic Mouse); the built-in trackpad
        // does not always produce HID reports we can see, so trust the event itself.
        if type == .scrollWheel, event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
           !(d?.name.localizedCaseInsensitiveContains("Magic Mouse") ?? false) {
            d = Self.trackpadDevice
        }
        let key = d?.id ?? ""
        if d == device, !profileCache.isEmpty { return }
        device = d
        if let cached = profileCache[key] {
            profile = cached
        } else {
            profile = config.profile(for: d)
            profileCache[key] = profile
        }
    }

    // MARK: - Buttons

    private func mouseDown(_ event: CGEvent) -> CGEvent? {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let location = event.location
        let now = Self.now
        let click = profile.click

        if click.debounce {
            debouncer.window = click.debounceMs / 1000
            if !debouncer.mouseDown(button: button, time: now) {
                counters.bouncesFiltered += 1
                return nil
            }
        }

        // Any click ends autoscroll and is consumed.
        if middle.isAutoscrolling {
            _ = middle.mouseDown(button: button, location: location)
            return nil
        }

        let action = button >= 2 ? profile.buttons.action(for: button) : .none

        if button == MiddleButtonScroll.middle, action == .none, profile.scroll.middleButton != .normal {
            middle.mode = profile.scroll.middleButton
            middle.panSpeed = profile.scroll.panSpeed
            if middle.mouseDown(button: button, location: location) == .swallow {
                startFrames()
                return nil
            }
        }

        if action != .none {
            consumed.insert(button)
            switch action {
            case .gesture:
                gesture.threshold = profile.buttons.gesture.threshold
                gesture.mouseDown(button: button, location: location)
                startFreeze(.gesture, at: location)
            case .precision:
                precisionButton = button
                pointer.setPrecision(true, device: device?.category == .mouse ? device : nil, factor: profile.pointer.precisionFactor)
            default:
                perform(action, at: location)
            }
            return nil
        }

        let eligible = click.stabilize && click.buttons.contains(button)
        stabilizer.settings = ClickStabilizer.Settings(
            enabled: true,
            radius: click.radius,
            maxDuration: click.maxDurationMs / 1000,
            cursorPinned: click.freezeCursor
        )
        _ = stabilizer.mouseDown(button: button, location: location, time: now, stabilize: eligible)
        if eligible, click.freezeCursor, freezeOwner == nil {
            startFreeze(.stabilizer, at: location)
        }

        if click.stuckGuard {
            stuckGuard.delivered(down: button, time: now)
            maintenanceTimer.start()
        }
        return event
    }

    private func mouseUp(_ event: CGEvent) -> CGEvent? {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let location = event.location
        let now = Self.now

        if profile.click.debounce, !debouncer.mouseUp(button: button, time: now) {
            return nil
        }

        switch middle.mouseUp(button: button) {
        case .swallow:
            endFreeze(.pan)
            return nil
        case let .click(at):
            EventSynth.click(button, at: at, flags: event.flags)
            return nil
        case .pass:
            break
        }

        if consumed.remove(button) != nil {
            if precisionButton == button {
                precisionButton = nil
                pointer.setPrecision(false, device: nil, factor: 1)
            }
            if gesture.heldButton == button {
                let origin = gesture.origin ?? location
                endFreeze(.gesture)
                if gesture.mouseUp(button: button) == true {
                    let clickAction = profile.buttons.gesture.click
                    if clickAction == .none {
                        // Plain click: let the button do what it natively does.
                        EventSynth.click(button, at: origin, flags: event.flags)
                    } else {
                        perform(clickAction, at: origin)
                    }
                }
            }
            return nil
        }

        let (decision, record) = stabilizer.mouseUp(button: button, location: location, time: now)
        endFreeze(.stabilizer)
        if let record {
            diagnostics.add(record, device: device?.name ?? "—")
        }
        if case let .relocate(origin) = decision {
            event.location = origin
        }
        stuckGuard.delivered(up: button)
        return event
    }

    private func mouseDragged(_ event: CGEvent) -> CGEvent? {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let delta = CGVector(
            dx: event.getDoubleValueField(.mouseEventDeltaX),
            dy: event.getDoubleValueField(.mouseEventDeltaY)
        )

        switch middle.mouseDragged(button: button, delta: delta) {
        case .swallow:
            return nil
        case let .scroll(v):
            if freezeOwner == nil, let origin = middle.origin {
                startFreeze(.pan, at: origin)
            } else {
                freeze.hold()
            }
            EventSynth.scroll(dx: Int32(v.dx.rounded()), dy: Int32(v.dy.rounded()), flags: event.flags, location: middle.origin)
            return nil
        case .pass:
            break
        }

        if consumed.contains(button) {
            if gesture.heldButton == button {
                freeze.hold()
                if let direction = gesture.mouseDragged(button: button, delta: delta) {
                    perform(directionAction(direction), at: gesture.origin ?? event.location)
                }
            }
            return nil
        }

        switch stabilizer.mouseDragged(button: button, location: event.location, delta: delta, time: Self.now) {
        case .swallow:
            if freezeOwner == .stabilizer { freeze.hold() }
            return nil
        case let .release(location, total):
            endFreeze(.stabilizer, at: location)
            event.location = location
            event.setDoubleValueField(.mouseEventDeltaX, value: total.dx)
            event.setDoubleValueField(.mouseEventDeltaY, value: total.dy)
            return event
        case .pass, .relocate:
            return event
        }
    }

    private func directionAction(_ direction: GestureButton.Direction) -> ButtonAction {
        let g = profile.buttons.gesture
        switch direction {
        case .left: return g.left
        case .right: return g.right
        case .up: return g.up
        case .down: return g.down
        }
    }

    // MARK: - Scroll

    private func scrollWheel(_ event: CGEvent) -> CGEvent? {
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let flags = event.flags
        let modifiers = Modifiers(flags)
        var dy = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        var dx = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        if dy == 0, dx == 0 {
            dy = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            dx = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        }
        let now = Self.now

        if !continuous {
            // Rotation first: its default modifiers (⌘⌥) are a superset of zoom's (⌘).
            if config.rotate.enabled, modifiers == config.rotate.modifiers, dy != 0 {
                let degrees = physical(dy, event) * config.rotate.degreesPerLine
                emit(rotation.input(degrees, time: now), magnify: false)
                startFrames()
                return nil
            }
            if config.zoom.enabled, modifiers == config.zoom.modifiers, dy != 0 {
                zoomStep(physical(dy, event), event: event, now: now)
                return nil
            }
        }

        if profile.scroll.reverseVertical { dy = -dy }
        if profile.scroll.reverseHorizontal { dx = -dx }

        if !continuous, profile.scroll.smooth {
            if modifiers.contains(.shift), dx == 0 {
                // Continuous events lose AppKit's shift→horizontal mapping; do it ourselves.
                dx = dy
                dy = 0
            }
            scroller.settings = SmoothScroller.Settings(
                pixelsPerLine: profile.scroll.speed,
                acceleration: profile.scroll.acceleration,
                tau: profile.scroll.inertiaMs / 1000
            )
            scroller.input(lines: CGVector(dx: dx, dy: dy), time: now)
            scrollFlags = flags
            startFrames()
            return nil
        }

        if profile.scroll.reverseVertical { Self.negate(event, axis: 1) }
        if profile.scroll.reverseHorizontal { Self.negate(event, axis: 2) }
        return event
    }

    /// Wheel direction as the hand moved it, undoing macOS "natural scrolling".
    private func physical(_ lines: Double, _ event: CGEvent) -> Double {
        let inverted = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false
        return inverted ? -lines : lines
    }

    private func zoomStep(_ lines: Double, event: CGEvent, now: TimeInterval) {
        let zoomIn = (lines > 0) != config.zoom.invert
        if let app = frontmostApp.withLock({ $0 }), config.zoom.keyFallbackApps.contains(app) {
            let key = zoomIn ? EventSynth.KeyCode.equal : EventSynth.KeyCode.minus
            actions.async { EventSynth.keyStroke(key, modifiers: .maskCommand) }
            return
        }
        let amount = min(abs(lines), 4) * 0.045 * config.zoom.sensitivity * (zoomIn ? 1 : -1)
        emit(zoom.input(amount, time: now), magnify: true)
        startFrames()
    }

    private static func negate(_ event: CGEvent, axis: Int) {
        let fields: [CGEventField] = axis == 1
            ? [.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1]
            : [.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2]
        for field in fields {
            if field == .scrollWheelEventFixedPtDeltaAxis1 || field == .scrollWheelEventFixedPtDeltaAxis2 {
                event.setDoubleValueField(field, value: -event.getDoubleValueField(field))
            } else {
                event.setIntegerValueField(field, value: -event.getIntegerValueField(field))
            }
        }
    }

    private func emit(_ outputs: [GestureSmoother.Output], magnify: Bool) {
        for output in outputs {
            switch output {
            case .began:
                magnify ? EventSynth.magnify(0, phase: .began) : EventSynth.rotate(0, phase: .began)
            case let .changed(v):
                magnify ? EventSynth.magnify(v, phase: .changed) : EventSynth.rotate(v, phase: .changed)
            case .ended:
                magnify ? EventSynth.magnify(0, phase: .ended) : EventSynth.rotate(0, phase: .ended)
            }
        }
    }

    // MARK: - Timers

    private func startFrames() {
        guard !frameTimer.isRunning else { return }
        lastFrame = Self.now
        frameTimer.start()
    }

    private func frame() {
        let now = Self.now
        let dt = min(max(now - lastFrame, 0.001), 0.05)
        lastFrame = now

        emit(zoom.tick(time: now, dt: dt), magnify: true)
        emit(rotation.tick(time: now, dt: dt), magnify: false)

        if scroller.isActive {
            let step = scroller.tick(dt: dt)
            EventSynth.scroll(dx: step.dx, dy: step.dy, flags: scrollFlags)
        }

        if middle.isAutoscrolling, let cursor = CGEvent(source: nil)?.location,
           let v = middle.autoscrollStep(cursor: cursor, dt: dt) {
            autoscrollCarry.dx += v.dx
            autoscrollCarry.dy += v.dy
            let ix = autoscrollCarry.dx.rounded(.towardZero)
            let iy = autoscrollCarry.dy.rounded(.towardZero)
            autoscrollCarry.dx -= ix
            autoscrollCarry.dy -= iy
            EventSynth.scroll(dx: Int32(ix), dy: Int32(iy), flags: [], location: middle.origin)
        }

        let busy = zoom.isActive || rotation.isActive || scroller.isActive || middle.isAutoscrolling
            || middle.origin != nil
        if !busy {
            frameTimer.stop()
            autoscrollCarry = .zero
        }
    }

    private func maintenance() {
        let stuck = stuckGuard.check(time: Self.now) { button in
            CGEventSource.buttonState(.hidSystemState, button: CGMouseButton(rawValue: UInt32(button)) ?? .left)
        }
        if !stuck.isEmpty {
            counters.stuckReleases += stuck.count
            let location = CGEvent(source: nil)?.location ?? .zero
            for button in stuck {
                stabilizer.reset()
                EventSynth.mouseButton(button, down: false, at: location)
            }
        }
        publishCounters()
        if !stuckGuard.hasPressedButtons { maintenanceTimer.stop() }
    }

    func publishCounters() {
        counters.activeDevice = device?.name
        counters.inputMonitoring = devices.inputOpen
        diagnostics.update(counters)
    }

    /// After macOS disabled the tap we may have missed releases: drop transient state
    /// and let the stuck-button guard reconcile with the hardware right away.
    private func recoverAfterTapLoss() {
        stabilizer.reset()
        gesture.cancel()
        middle.cancel()
        consumed.removeAll()
        if precisionButton != nil {
            precisionButton = nil
            pointer.setPrecision(false, device: nil, factor: 1)
        }
        endFreeze(nil)
        if stuckGuard.hasPressedButtons { maintenance() }
    }

    // MARK: - Pointer freeze

    private func startFreeze(_ owner: FreezeOwner, at point: CGPoint) {
        guard freezeOwner == nil || freezeOwner == owner else { return }
        freezeOwner = owner
        freeze.freeze(at: point)
    }

    /// `owner` nil releases regardless of owner.
    private func endFreeze(_ owner: FreezeOwner?, at point: CGPoint? = nil) {
        guard freezeOwner != nil, owner == nil || freezeOwner == owner else { return }
        freezeOwner = nil
        freeze.release(at: point)
    }

    // MARK: - Actions

    private func perform(_ action: ButtonAction, at location: CGPoint) {
        switch action {
        case .none, .gesture, .precision:
            break
        case .back:
            actions.async { EventSynth.keyStroke(EventSynth.KeyCode.leftBracket, modifiers: .maskCommand) }
        case .forward:
            actions.async { EventSynth.keyStroke(EventSynth.KeyCode.rightBracket, modifiers: .maskCommand) }
        case .spaceLeft:
            actions.async { EventSynth.symbolicHotKey(.spaceLeft) }
        case .spaceRight:
            actions.async { EventSynth.symbolicHotKey(.spaceRight) }
        case .missionControl:
            actions.async { EventSynth.dock("com.apple.expose.awake") }
        case .appExpose:
            actions.async { EventSynth.dock("com.apple.expose.front.awake") }
        case .showDesktop:
            actions.async { EventSynth.dock("com.apple.showdesktop.awake") }
        case .launchpad:
            actions.async { EventSynth.dock("com.apple.launchpad.toggle") }
        case .smartZoom:
            EventSynth.smartZoom()
        case .nextDisplay:
            DisplayJump.nextDisplay(from: location)
        case .middleClick:
            EventSynth.click(MiddleButtonScroll.middle, at: location)
        }
    }

    func resetAll() {
        recoverAfterTapLoss()
        stuckGuard.reset()
        debouncer.reset()
        scroller.stop()
        emit(zoom.finish(), magnify: true)
        emit(rotation.finish(), magnify: false)
        frameTimer.stop()
        maintenanceTimer.stop()
    }
}
