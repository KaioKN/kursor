import Foundation
import os

/// Thread-safe store the event thread writes click records into and the UI polls.
public final class Diagnostics: @unchecked Sendable {
    public struct ClickEntry: Identifiable, Equatable, Sendable {
        public var id: Int
        public var date: Date
        public var device: String
        public var record: ClickStabilizer.Record
    }

    public struct Counters: Equatable, Sendable {
        public var events = 0
        public var tapReenabled = 0
        public var stuckReleases = 0
        public var bouncesFiltered = 0
        public var activeDevice: String?
        public var inputMonitoring = false

        public init() {}
    }

    struct State {
        var entries: [ClickEntry] = []
        var nextID = 0
        var counters = Counters()
    }

    public static let capacity = 500
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    func add(_ record: ClickStabilizer.Record, device: String) {
        state.withLock { s in
            s.entries.append(ClickEntry(id: s.nextID, date: Date(), device: device, record: record))
            s.nextID += 1
            if s.entries.count > Self.capacity { s.entries.removeFirst(s.entries.count - Self.capacity) }
        }
    }

    func update(_ counters: Counters) {
        state.withLock { $0.counters = counters }
    }

    public func snapshot() -> (entries: [ClickEntry], counters: Counters) {
        state.withLock { ($0.entries, $0.counters) }
    }

    public func clear() {
        state.withLock { $0.entries.removeAll() }
    }
}

public extension Array where Element == Diagnostics.ClickEntry {
    /// Suggested stabilizer radius: 95th percentile of movement during non-drag clicks, plus margin.
    func suggestedRadius() -> Double? {
        let distances = filter { $0.record.outcome != .drag }.map(\.record.maxDistance).sorted()
        guard distances.count >= 10 else { return nil }
        let p95 = distances[Swift.min(distances.count - 1, Int(Double(distances.count) * 0.95))]
        return Swift.min(Swift.max((p95 + 1.5).rounded(), 2), 15)
    }
}
