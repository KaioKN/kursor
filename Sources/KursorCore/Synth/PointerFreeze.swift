import CoreGraphics
import Foundation

/// Pins the visible cursor while the mouse keeps producing deltas, by warping it back
/// to the origin on every movement event. A warp normally suppresses local mouse input
/// for 0.25 s; while frozen that interval is lowered so the pin feels instant
/// (approach and value from Mac Mouse Fix's PointerFreeze).
final class PointerFreeze {
    private(set) var origin: CGPoint?
    private var savedInterval: CFTimeInterval?
    private let source = CGEventSource(stateID: .combinedSessionState)

    var isFrozen: Bool { origin != nil }

    func freeze(at point: CGPoint) {
        if origin == nil, let source {
            savedInterval = source.localEventsSuppressionInterval
            source.localEventsSuppressionInterval = 0.05
        }
        origin = point
        CGWarpMouseCursorPosition(point)
    }

    /// Call for every swallowed movement event while frozen.
    func hold() {
        guard let origin else { return }
        CGWarpMouseCursorPosition(origin)
    }

    /// Unfreezes; optionally moves the cursor to `point` first.
    func release(at point: CGPoint? = nil) {
        guard origin != nil else { return }
        if let point { CGWarpMouseCursorPosition(point) }
        if let source, let savedInterval { source.localEventsSuppressionInterval = savedInterval }
        savedInterval = nil
        origin = nil
        // Re-associate right away so the post-warp suppression does not stall the cursor.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
