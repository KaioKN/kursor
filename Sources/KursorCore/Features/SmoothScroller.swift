import CoreGraphics
import Foundation

/// Converts wheel lines into a decaying stream of whole-pixel scroll steps.
public final class SmoothScroller {
    public struct Settings: Equatable {
        public var pixelsPerLine: Double
        public var acceleration: Double
        public var tau: TimeInterval

        public init(pixelsPerLine: Double = 40, acceleration: Double = 0.6, tau: TimeInterval = 0.11) {
            self.pixelsPerLine = pixelsPerLine
            self.acceleration = acceleration
            self.tau = tau
        }
    }

    public var settings: Settings
    private var remaining = CGVector.zero
    private var carry = CGVector.zero
    private var rate: Double = 0
    private var lastInput: TimeInterval = -1

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    public var isActive: Bool {
        abs(remaining.dx) >= 0.5 || abs(remaining.dy) >= 0.5 || abs(carry.dx) >= 1 || abs(carry.dy) >= 1
    }

    /// Wheel spin rate (notches/s) → distance multiplier.
    func accelerationFactor() -> Double {
        1 + settings.acceleration * min(max((rate - 6) / 10, 0), 3)
    }

    public func input(lines: CGVector, time: TimeInterval) {
        let dt = lastInput < 0 ? 1 : time - lastInput
        lastInput = time
        if dt < 0.3, dt > 0 {
            rate = 0.6 * rate + 0.4 * min(1 / dt, 80)
        } else {
            rate = 0
        }

        // Reversing direction stops the glide instead of fighting it.
        if lines.dy != 0, remaining.dy != 0, (lines.dy > 0) != (remaining.dy > 0) {
            remaining.dy = 0
            carry.dy = 0
        }
        if lines.dx != 0, remaining.dx != 0, (lines.dx > 0) != (remaining.dx > 0) {
            remaining.dx = 0
            carry.dx = 0
        }

        let k = settings.pixelsPerLine * accelerationFactor()
        remaining.dx += lines.dx * k
        remaining.dy += lines.dy * k
    }

    /// Pixel step for this frame (integers, sub-pixel remainder carried over).
    public func tick(dt: TimeInterval) -> (dx: Int32, dy: Int32) {
        let f = settings.tau > 0 ? 1 - exp(-max(dt, 0) / settings.tau) : 1
        var step = CGVector(dx: remaining.dx * f, dy: remaining.dy * f)
        if abs(remaining.dx) < 1 { step.dx = remaining.dx }
        if abs(remaining.dy) < 1 { step.dy = remaining.dy }
        remaining.dx -= step.dx
        remaining.dy -= step.dy
        carry.dx += step.dx
        carry.dy += step.dy
        let ix = carry.dx.rounded(.towardZero)
        let iy = carry.dy.rounded(.towardZero)
        carry.dx -= ix
        carry.dy -= iy
        if !isActive {
            carry = .zero
            remaining = .zero
        }
        return (Int32(ix), Int32(iy))
    }

    public func stop() {
        remaining = .zero
        carry = .zero
    }
}
