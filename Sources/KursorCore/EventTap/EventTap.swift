import CoreGraphics
import Foundation

/// Active HID-level event tap. HID level sees events before the window server routes
/// them, so a swallowed drag never reaches any app or window-dragging logic.
final class EventTap {
    private(set) var port: CFMachPort?
    private var source: CFRunLoopSource?

    static let mask: CGEventMask = [
        CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .scrollWheel,
    ].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

    /// Fails without Accessibility permission.
    func install(on runLoop: CFRunLoop, callback: CGEventTapCallBack, userInfo: UnsafeMutableRawPointer) -> Bool {
        remove()
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.mask,
            callback: callback,
            userInfo: userInfo
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    var isEnabled: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    func enable() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func remove() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source { CFRunLoopSourceInvalidate(source) }
        port = nil
        source = nil
    }
}
