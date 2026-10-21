import CoreGraphics
import Foundation

/// Hold a button and move: once the movement passes `threshold`, the dominant
/// direction fires. Horizontal gestures may repeat within one hold (switch several
/// spaces); vertical ones fire once.
public final class GestureButton {
    public enum Direction: Equatable, Sendable { case left, right, up, down }

    struct Hold {
        var button: ButtonNumber
        var origin: CGPoint
        var offset = CGVector.zero
        var fired: [Direction] = []
    }

    public var threshold: Double
    private(set) var hold: Hold?

    public init(threshold: Double = 60) {
        self.threshold = threshold
    }

    public var isHolding: Bool { hold != nil }
    public var heldButton: ButtonNumber? { hold?.button }
    public var origin: CGPoint? { hold?.origin }

    public func mouseDown(button: ButtonNumber, location: CGPoint) {
        hold = Hold(button: button, origin: location)
    }

    public func mouseDragged(button: ButtonNumber, delta: CGVector) -> Direction? {
        guard var h = hold, h.button == button else { return nil }
        defer { hold = h }
        h.offset.dx += delta.dx
        h.offset.dy += delta.dy

        let needed = h.fired.isEmpty ? threshold : threshold * 2
        guard h.offset.length >= needed else { return nil }

        let direction: Direction
        if abs(h.offset.dx) >= abs(h.offset.dy) {
            direction = h.offset.dx < 0 ? .left : .right
        } else {
            // CG coordinates: y grows downward.
            direction = h.offset.dy < 0 ? .up : .down
        }
        let vertical = direction == .up || direction == .down
        if let last = h.fired.last {
            let lastVertical = last == .up || last == .down
            guard !vertical, !lastVertical else {
                h.offset = .zero
                return nil
            }
        }
        h.fired.append(direction)
        h.offset = .zero
        return direction
    }

    /// Returns true when nothing fired during the hold (treat it as a click).
    public func mouseUp(button: ButtonNumber) -> Bool? {
        guard let h = hold, h.button == button else { return nil }
        hold = nil
        return h.fired.isEmpty
    }

    public func cancel() {
        hold = nil
    }
}
