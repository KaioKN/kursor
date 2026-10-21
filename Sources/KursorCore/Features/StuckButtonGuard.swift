import Foundation

/// Tracks which buttons apps currently believe are held (what left the pipeline) and
/// reports those the hardware has already released, e.g. after a lost mouse-up.
public final class StuckButtonGuard {
    /// Hardware must report "up" for this long before we synthesize a release,
    /// so a real release that is still in flight is never duplicated.
    public var grace: TimeInterval
    private var pressed: [ButtonNumber: TimeInterval] = [:]
    private var upSince: [ButtonNumber: TimeInterval] = [:]
    public private(set) var releasesSynthesized = 0

    public init(grace: TimeInterval = 0.4) {
        self.grace = grace
    }

    public var hasPressedButtons: Bool { !pressed.isEmpty }
    public var pressedButtons: [ButtonNumber] { Array(pressed.keys).sorted() }

    public func delivered(down button: ButtonNumber, time: TimeInterval) {
        pressed[button] = time
        upSince[button] = nil
    }

    public func delivered(up button: ButtonNumber) {
        pressed[button] = nil
        upSince[button] = nil
    }

    /// `hardwareDown` reports the live hardware state. Returns buttons that need a synthetic release.
    public func check(time: TimeInterval, hardwareDown: (ButtonNumber) -> Bool) -> [ButtonNumber] {
        var stuck: [ButtonNumber] = []
        for button in pressed.keys.sorted() {
            if hardwareDown(button) {
                upSince[button] = nil
                continue
            }
            let since = upSince[button] ?? time
            upSince[button] = since
            if time - since >= grace {
                stuck.append(button)
            }
        }
        for button in stuck {
            pressed[button] = nil
            upSince[button] = nil
        }
        releasesSynthesized += stuck.count
        return stuck
    }

    public func reset() {
        pressed.removeAll()
        upSince.removeAll()
    }
}
