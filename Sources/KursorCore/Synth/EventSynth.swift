import AppKit
import CoreGraphics
import KursorSPI

/// Creates and posts synthetic events. Every event we post carries `marker` in
/// `eventSourceUserData`, so our own tap passes it through untouched.
public enum EventSynth {
    public static let marker: Int64 = 0x4B55_5253 // "KURS"

    public static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    public static func post(_ event: CGEvent, tap: CGEventTapLocation = .cghidEventTap) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: tap)
    }

    // MARK: - Trackpad gestures
    //
    // Undocumented fields, first reverse-engineered in CalfTrail "Touch" and used by
    // Mac Mouse Fix's TouchSimulator: type 29 = NSEventTypeGesture, field 110 = IOHID
    // event subtype, 132 = phase, 113 = magnification, 114 = rotation.

    public enum Phase: Int64 {
        case began = 1
        case changed = 2
        case ended = 4
        case cancelled = 8
    }

    enum Field {
        static let subtype: UInt32 = 110
        static let magnification: UInt32 = 113
        static let rotation: UInt32 = 114
        static let phase: UInt32 = 132
    }

    enum Subtype {
        static let rotation: Int64 = 5
        static let zoom: Int64 = 8
        static let zoomToggle: Int64 = 22
    }

    static let gestureType: UInt32 = 29

    private static func gestureEvent(subtype: Int64) -> CGEvent? {
        guard let e = CGEvent(source: nil) else { return nil }
        KursorEventSetType(e, gestureType)
        KursorEventSetInt(e, Field.subtype, subtype)
        // Gestures must not inherit the held zoom modifier (⌘), or apps treat them as shortcuts.
        e.flags = []
        return e
    }

    public static func magnify(_ amount: Double, phase: Phase) {
        guard let e = gestureEvent(subtype: Subtype.zoom) else { return }
        KursorEventSetInt(e, Field.phase, phase.rawValue)
        KursorEventSetDouble(e, Field.magnification, amount)
        post(e)
    }

    public static func rotate(_ degrees: Double, phase: Phase) {
        guard let e = gestureEvent(subtype: Subtype.rotation) else { return }
        KursorEventSetInt(e, Field.phase, phase.rawValue)
        KursorEventSetDouble(e, Field.rotation, degrees)
        post(e)
    }

    /// Two-finger double tap ("smart zoom").
    public static func smartZoom() {
        guard let e = gestureEvent(subtype: Subtype.zoomToggle) else { return }
        post(e)
    }

    // MARK: - Scroll

    /// Continuous pixel scroll, like a trackpad without phases. Positive dy scrolls up.
    public static func scroll(dx: Int32, dy: Int32, flags: CGEventFlags, location: CGPoint? = nil) {
        guard dx != 0 || dy != 0,
              let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        else { return }
        e.flags = flags
        if let location { e.location = location }
        post(e)
    }

    // MARK: - Mouse buttons

    static func mouseTypes(for button: ButtonNumber) -> (down: CGEventType, up: CGEventType, mouseButton: CGMouseButton) {
        switch button {
        case 0: return (.leftMouseDown, .leftMouseUp, .left)
        case 1: return (.rightMouseDown, .rightMouseUp, .right)
        default: return (.otherMouseDown, .otherMouseUp, CGMouseButton(rawValue: UInt32(button)) ?? .center)
        }
    }

    public static func mouseButton(_ button: ButtonNumber, down: Bool, at location: CGPoint, flags: CGEventFlags = []) {
        let t = mouseTypes(for: button)
        guard let e = CGEvent(mouseEventSource: nil, mouseType: down ? t.down : t.up, mouseCursorPosition: location, mouseButton: t.mouseButton) else { return }
        e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        e.setIntegerValueField(.mouseEventClickState, value: 1)
        e.flags = flags
        post(e)
    }

    public static func click(_ button: ButtonNumber, at location: CGPoint, flags: CGEventFlags = []) {
        mouseButton(button, down: true, at: location, flags: flags)
        mouseButton(button, down: false, at: location, flags: flags)
    }

    // MARK: - Keyboard

    enum KeyCode {
        static let leftBracket: CGKeyCode = 0x21
        static let rightBracket: CGKeyCode = 0x1E
        static let equal: CGKeyCode = 0x18
        static let minus: CGKeyCode = 0x1B
        static let command: CGKeyCode = 0x37
        static let shift: CGKeyCode = 0x38
        static let option: CGKeyCode = 0x3A
        static let control: CGKeyCode = 0x3B
    }

    /// Key press wrapped in explicit modifier flagsChanged events, like a real keyboard;
    /// otherwise the system's modifier state can stay "held".
    public static func keyStroke(_ key: CGKeyCode, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let mods: [(CGEventFlags, CGKeyCode)] = [
            (.maskShift, KeyCode.shift), (.maskControl, KeyCode.control),
            (.maskAlternate, KeyCode.option), (.maskCommand, KeyCode.command),
        ].filter { modifiers.contains($0.0) }

        var held: CGEventFlags = []
        for (flag, code) in mods {
            held.insert(flag)
            if let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
                e.type = .flagsChanged
                e.flags = held
                post(e, tap: .cgSessionEventTap)
            }
        }
        for down in [true, false] {
            if let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) {
                e.flags = modifiers
                post(e, tap: .cgSessionEventTap)
            }
        }
        for (flag, code) in mods.reversed() {
            held.remove(flag)
            if let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
                e.type = .flagsChanged
                e.flags = held
                post(e, tap: .cgSessionEventTap)
            }
        }
    }

    // MARK: - System actions

    public enum SymbolicHotKey: UInt32 {
        case spaceLeft = 79
        case spaceRight = 81
    }

    /// Triggers a system shortcut (e.g. "Move left a space") with whatever keys the user
    /// configured for it, temporarily enabling it if it is switched off.
    @discardableResult
    public static func symbolicHotKey(_ hotKey: SymbolicHotKey) -> Bool {
        var keyEquivalent: UInt16 = 0
        var virtualKey: UInt16 = 0
        var modifiers: UInt32 = 0
        guard CGSGetSymbolicHotKeyValue(hotKey.rawValue, &keyEquivalent, &virtualKey, &modifiers) == .success,
              virtualKey != 0xFFFF, virtualKey != 0 || keyEquivalent != 0xFFFF
        else { return false }

        let wasEnabled = CGSIsSymbolicHotKeyEnabled(hotKey.rawValue)
        if !wasEnabled { CGSSetSymbolicHotKeyEnabled(hotKey.rawValue, true) }
        keyStroke(CGKeyCode(virtualKey), modifiers: CGEventFlags(rawValue: UInt64(modifiers)))
        if !wasEnabled {
            // Give the window server time to consume the keystroke before disabling again.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                CGSSetSymbolicHotKeyEnabled(hotKey.rawValue, false)
            }
        }
        return true
    }

    public static func dock(_ notification: String) {
        _ = CoreDockSendNotification(notification as CFString, 0)
    }
}
