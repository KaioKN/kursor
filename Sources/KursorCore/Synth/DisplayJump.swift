import CoreGraphics
import Foundation

/// Moves the cursor to the same relative spot on the next display (left-to-right order).
enum DisplayJump {
    static func nextDisplay(from point: CGPoint) {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 1 else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        let bounds = ids.map { CGDisplayBounds($0) }.sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
        guard let current = bounds.firstIndex(where: { $0.contains(point) }) else { return }
        let from = bounds[current]
        let to = bounds[(current + 1) % bounds.count]

        let rx = (point.x - from.minX) / from.width
        let ry = (point.y - from.minY) / from.height
        let target = CGPoint(x: to.minX + rx * to.width, y: to.minY + ry * to.height)
        CGWarpMouseCursorPosition(target)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
