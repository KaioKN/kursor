import Foundation

/// Drops switch bounce: a press arriving within `window` of the previous release of the
/// same button is swallowed together with its release.
public final class Debouncer {
    public var window: TimeInterval
    private var lastUp: [ButtonNumber: TimeInterval] = [:]
    private var swallowNextUp: Set<ButtonNumber> = []
    public private(set) var bouncesFiltered = 0

    public init(window: TimeInterval = 0.03) {
        self.window = window
    }

    /// Returns false when the press must be swallowed.
    public func mouseDown(button: ButtonNumber, time: TimeInterval) -> Bool {
        if let up = lastUp[button], time - up < window {
            swallowNextUp.insert(button)
            bouncesFiltered += 1
            return false
        }
        return true
    }

    /// Returns false when the release belongs to a swallowed press.
    public func mouseUp(button: ButtonNumber, time: TimeInterval) -> Bool {
        if swallowNextUp.remove(button) != nil { return false }
        lastUp[button] = time
        return true
    }

    public func reset() {
        lastUp.removeAll()
        swallowNextUp.removeAll()
    }
}
