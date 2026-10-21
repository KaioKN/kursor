import Foundation

/// Turns discrete wheel steps into a smooth began → changed… → ended gesture stream
/// (used for pinch-zoom and rotation).
public final class GestureSmoother {
    public enum Output: Equatable {
        case began
        case changed(Double)
        case ended
    }

    /// Glide time constant; 0 = emit each input immediately.
    public var tau: TimeInterval
    /// Idle time after the last input before the gesture ends.
    public var endDelay: TimeInterval
    public private(set) var isActive = false
    private var pending: Double = 0
    private var lastInput: TimeInterval = 0
    private let epsilon = 1e-5

    public init(tau: TimeInterval = 0.045, endDelay: TimeInterval = 0.16) {
        self.tau = tau
        self.endDelay = endDelay
    }

    public func input(_ amount: Double, time: TimeInterval) -> [Output] {
        var out: [Output] = []
        if !isActive {
            isActive = true
            out.append(.began)
        }
        pending += amount
        lastInput = time
        return out
    }

    public func tick(time: TimeInterval, dt: TimeInterval) -> [Output] {
        guard isActive else { return [] }
        if abs(pending) > epsilon {
            var step = tau > 0 ? pending * (1 - exp(-max(dt, 0) / tau)) : pending
            if abs(pending) < 0.002 { step = pending }
            pending -= step
            return [.changed(step)]
        }
        if time - lastInput >= endDelay {
            isActive = false
            pending = 0
            return [.ended]
        }
        return []
    }

    /// Ends immediately (e.g. modifier released); returns the remaining change + end.
    public func finish() -> [Output] {
        guard isActive else { return [] }
        var out: [Output] = []
        if abs(pending) > epsilon { out.append(.changed(pending)) }
        out.append(.ended)
        pending = 0
        isActive = false
        return out
    }
}
