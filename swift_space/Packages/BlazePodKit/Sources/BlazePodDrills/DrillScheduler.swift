import Foundation

/// Clock + one-shot timers for the drill engine. Injected so tests can run on virtual time.
public protocol DrillScheduler: AnyObject {
    var now: TimeInterval { get }
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> DrillTimer
}

public final class DrillTimer {
    private var onCancel: (() -> Void)?
    public private(set) var isCancelled = false

    public init(onCancel: (() -> Void)? = nil) { self.onCancel = onCancel }

    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel?()
        onCancel = nil
    }
}

/// Production scheduler: main queue, monotonic clock.
public final class MainQueueScheduler: DrillScheduler {
    public init() {}

    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    public func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> DrillTimer {
        let work = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
        return DrillTimer { work.cancel() }
    }
}

/// Deterministic scheduler for tests: time only moves on `advance(by:)`.
public final class ManualScheduler: DrillScheduler {
    private struct Entry { let id: Int; let due: TimeInterval; let timer: DrillTimer; let action: () -> Void }
    private var entries: [Entry] = []
    private var nextID = 0
    public private(set) var now: TimeInterval = 0

    public init() {}

    public func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) -> DrillTimer {
        let timer = DrillTimer()
        entries.append(Entry(id: nextID, due: now + max(0, delay), timer: timer, action: action))
        nextID += 1
        return timer
    }

    /// Runs every timer due within the interval, in order, moving `now` along.
    public func advance(by interval: TimeInterval) {
        let end = now + interval
        while let next = entries.filter({ !$0.timer.isCancelled && $0.due <= end })
            .min(by: { ($0.due, $0.id) < ($1.due, $1.id) }) {
            entries.removeAll { $0.id == next.id }
            now = next.due
            next.action()
        }
        entries.removeAll { $0.timer.isCancelled }
        now = end
    }
}
