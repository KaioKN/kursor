import CoreGraphics
import Foundation

/// Middle button as a scroll tool.
/// - pan: hold and drag, the document follows the hand; a click without movement stays a click.
/// - autoscroll: a click toggles Windows-style autoscroll around an anchor point.
public final class MiddleButtonScroll {
    public enum DownDecision: Equatable { case pass, swallow }
    public enum DragDecision: Equatable { case pass, swallow, scroll(CGVector) }
    public enum UpDecision: Equatable { case pass, swallow, click(CGPoint) }

    enum State: Equatable {
        case idle
        case pressed(origin: CGPoint, offset: CGVector)
        case panning(origin: CGPoint)
        case autoscrolling(anchor: CGPoint)
        /// A click that ended autoscroll; its release must be swallowed too.
        case swallowingUp(ButtonNumber)
    }

    public static let middle: ButtonNumber = 2

    public var mode: MiddleButtonMode
    public var panSpeed: Double
    public var threshold: Double = 6
    /// Autoscroll dead zone (px) and gain (px/s per px of offset).
    public var deadZone: Double = 12
    public var autoscrollGain: Double = 5
    private(set) var state: State = .idle

    public init(mode: MiddleButtonMode = .pan, panSpeed: Double = 1) {
        self.mode = mode
        self.panSpeed = panSpeed
    }

    public var isAutoscrolling: Bool {
        if case .autoscrolling = state { return true }
        return false
    }

    public var isPanning: Bool {
        if case .panning = state { return true }
        return false
    }

    public var origin: CGPoint? {
        switch state {
        case let .pressed(origin, _), let .panning(origin): return origin
        case let .autoscrolling(anchor): return anchor
        default: return nil
        }
    }

    public func mouseDown(button: ButtonNumber, location: CGPoint) -> DownDecision {
        if isAutoscrolling {
            state = .swallowingUp(button)
            return .swallow
        }
        guard mode != .normal, button == Self.middle, state == .idle else { return .pass }
        state = .pressed(origin: location, offset: .zero)
        return .swallow
    }

    public func mouseDragged(button: ButtonNumber, delta: CGVector) -> DragDecision {
        switch state {
        case let .pressed(origin, offset) where button == Self.middle:
            let total = CGVector(dx: offset.dx + delta.dx, dy: offset.dy + delta.dy)
            if total.length > threshold {
                state = .panning(origin: origin)
                return .scroll(panDelta(total))
            }
            state = .pressed(origin: origin, offset: total)
            return .swallow
        case .panning where button == Self.middle:
            return .scroll(panDelta(delta))
        case let .swallowingUp(b) where b == button:
            return .swallow
        default:
            return .pass
        }
    }

    public func mouseUp(button: ButtonNumber) -> UpDecision {
        switch state {
        case let .pressed(origin, _) where button == Self.middle:
            if mode == .autoscroll {
                state = .autoscrolling(anchor: origin)
                return .swallow
            }
            state = .idle
            return .click(origin)
        case .panning where button == Self.middle:
            state = .idle
            return .swallow
        case let .swallowingUp(b) where b == button:
            state = .idle
            return .swallow
        default:
            return .pass
        }
    }

    /// Autoscroll velocity step for the current cursor position (pixel scroll units).
    public func autoscrollStep(cursor: CGPoint, dt: TimeInterval) -> CGVector? {
        guard case let .autoscrolling(anchor) = state else { return nil }
        let offset = cursor - anchor
        let distance = offset.length
        guard distance > deadZone else { return .zero }
        let speed = (distance - deadZone) * autoscrollGain
        let scale = speed * dt / distance
        // Cursor below the anchor scrolls down (negative wheel delta).
        return CGVector(dx: -offset.dx * scale, dy: -offset.dy * scale)
    }

    public func cancel() {
        state = .idle
    }

    /// Content follows the hand: dragging down reveals what is above (positive wheel delta).
    private func panDelta(_ v: CGVector) -> CGVector {
        CGVector(dx: v.dx * panSpeed, dy: v.dy * panSpeed)
    }
}
