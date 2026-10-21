import CoreGraphics
import Foundation

/// Keeps a click a click: while a button is down, drag events are swallowed until the
/// pointer leaves `radius` or `maxDuration` elapses. A release inside the window is
/// delivered at the press location, so apps see press+release with no drag in between.
public final class ClickStabilizer {
    public struct Settings: Equatable {
        public var enabled: Bool
        public var radius: Double
        public var maxDuration: TimeInterval
        /// The caller pins the visible cursor at the press point, so event locations stay
        /// there and the drag must be released at origin + accumulated movement.
        public var cursorPinned: Bool

        public init(enabled: Bool = true, radius: Double = 4, maxDuration: TimeInterval = 0.2, cursorPinned: Bool = false) {
            self.enabled = enabled
            self.radius = radius
            self.maxDuration = maxDuration
            self.cursorPinned = cursorPinned
        }
    }

    public enum Decision: Equatable {
        case pass
        case swallow
        /// First drag after leaving the window: deliver at `location` with the full
        /// accumulated `delta`, so no movement is lost.
        case release(location: CGPoint, delta: CGVector)
        /// Deliver the event at this location instead (the press point).
        case relocate(CGPoint)
    }

    public enum Outcome: String, Equatable, Sendable {
        /// No drag events at all.
        case clean
        /// Micro-drag swallowed: this click would have been a drag without Kursor.
        case stabilized
        /// Left the window, became a real drag.
        case drag
        /// Stabilizer off, but the click had drag events inside the window (would have been fixed).
        case microDrag
    }

    public struct Record: Equatable, Sendable {
        public var button: ButtonNumber
        public var duration: TimeInterval
        public var maxDistance: Double
        public var dragEvents: Int
        public var swallowed: Int
        public var outcome: Outcome
    }

    struct Session {
        var button: ButtonNumber
        var origin: CGPoint
        var start: TimeInterval
        var offset = CGVector.zero
        var maxDistance: Double = 0
        var dragEvents = 0
        var swallowed = 0
        var released = false
        var active: Bool
    }

    public var settings: Settings
    private(set) var session: Session?

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    public var isHolding: Bool { session.map { $0.active && !$0.released } ?? false }
    public var origin: CGPoint? { session?.origin }

    /// `stabilize` = this button on this device is eligible; when false the click is
    /// only measured (for diagnostics) and never altered.
    public func mouseDown(button: ButtonNumber, location: CGPoint, time: TimeInterval, stabilize: Bool) -> Decision {
        if var s = session, s.button != button {
            // A second button while one is held: stop interfering with the first.
            s.released = true
            session = s
            return .pass
        }
        session = Session(button: button, origin: location, start: time, active: stabilize && settings.enabled)
        return .pass
    }

    public func mouseDragged(button: ButtonNumber, location: CGPoint, delta: CGVector, time: TimeInterval) -> Decision {
        guard var s = session, s.button == button else { return .pass }
        defer { session = s }

        s.dragEvents += 1
        // Deltas are the hand's real movement whether or not the cursor followed it
        // (swallowed or pinned events may leave event locations near the origin).
        s.offset.dx += delta.dx
        s.offset.dy += delta.dy
        let distance = s.offset.length
        s.maxDistance = max(s.maxDistance, distance)

        guard s.active, !s.released else { return .pass }

        let inside = distance <= settings.radius && (time - s.start) <= settings.maxDuration
        if inside {
            s.swallowed += 1
            return .swallow
        }
        s.released = true
        let target = settings.cursorPinned ? s.origin + s.offset : location
        return .release(location: target, delta: target - s.origin)
    }

    public func mouseUp(button: ButtonNumber, location: CGPoint, time: TimeInterval) -> (Decision, Record?) {
        guard let s = session, s.button == button else { return (.pass, nil) }
        session = nil

        let outcome: Outcome
        if s.released, s.active {
            outcome = .drag
        } else if s.swallowed > 0 {
            outcome = .stabilized
        } else if s.dragEvents == 0 {
            outcome = .clean
        } else if !s.active, s.maxDistance <= settings.radius, (time - s.start) <= settings.maxDuration {
            outcome = .microDrag
        } else {
            outcome = .drag
        }
        let record = Record(
            button: button,
            duration: time - s.start,
            maxDistance: s.maxDistance,
            dragEvents: s.dragEvents,
            swallowed: s.swallowed,
            outcome: outcome
        )
        let decision: Decision = (s.active && !s.released) ? .relocate(s.origin) : .pass
        return (decision, record)
    }

    public func reset() {
        session = nil
    }
}
