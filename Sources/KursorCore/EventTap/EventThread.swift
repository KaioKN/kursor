import Foundation

/// Dedicated high-priority thread with its own run loop. The event tap, HID manager and
/// all feature state live here, so the hot path needs no locks.
final class EventThread: Thread {
    private(set) var runLoop: CFRunLoop!
    private let ready = DispatchSemaphore(value: 0)

    override init() {
        super.init()
        name = "app.kursor.events"
        qualityOfService = .userInteractive
    }

    func startAndWait() {
        start()
        ready.wait()
    }

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A port keeps the run loop alive while no tap source is installed yet.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !isCancelled {
            _ = autoreleasepool {
                RunLoop.current.run(mode: .default, before: .distantFuture)
            }
        }
    }

    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    func performAndWait<T>(_ block: @escaping () -> T) -> T {
        if Thread.current == self { return block() }
        var result: T?
        let done = DispatchSemaphore(value: 0)
        perform {
            result = block()
            done.signal()
        }
        done.wait()
        return result!
    }

    func stop() {
        cancel()
        CFRunLoopStop(runLoop)
    }
}

/// Repeating run-loop timer that can be started/stopped cheaply from its own thread.
final class RunLoopTimer {
    private let runLoop: CFRunLoop
    private let interval: TimeInterval
    private let handler: () -> Void
    private var timer: CFRunLoopTimer?

    init(runLoop: CFRunLoop, interval: TimeInterval, handler: @escaping () -> Void) {
        self.runLoop = runLoop
        self.interval = interval
        self.handler = handler
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        let t = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + interval, interval, 0, 0) { [weak self] _ in
            self?.handler()
        }
        CFRunLoopAddTimer(runLoop, t, .commonModes)
        timer = t
    }

    func stop() {
        guard let t = timer else { return }
        CFRunLoopTimerInvalidate(t)
        timer = nil
    }
}
