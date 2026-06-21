import Foundation

public actor SidekickActionQueue {
    private var pending: [SidekickAction] = []
    private var running: SidekickAction?

    public init() {}

    public var pendingCount: Int {
        pending.count
    }

    public var current: SidekickAction? {
        running
    }

    @discardableResult
    public func enqueue(_ action: SidekickAction) -> SidekickRequestSnapshot {
        pending.append(action)
        return SidekickRequestSnapshot(id: action.id, command: action.command, status: .queued)
    }

    public func startNext() -> SidekickRequestSnapshot? {
        guard running == nil, !pending.isEmpty else {
            return nil
        }
        let next = pending.removeFirst()
        running = next
        return SidekickRequestSnapshot(id: next.id, command: next.command, status: .running)
    }

    public func finishCurrent(status: SidekickRequestStatus = .complete) -> SidekickRequestSnapshot? {
        guard let running else {
            return nil
        }
        self.running = nil
        return SidekickRequestSnapshot(id: running.id, command: running.command, status: status)
    }

    public func stopCurrent() -> SidekickRequestSnapshot? {
        finishCurrent(status: .interrupted)
    }

    public func stopAll() -> [SidekickRequestSnapshot] {
        var interrupted: [SidekickRequestSnapshot] = []
        if let running {
            interrupted.append(SidekickRequestSnapshot(id: running.id, command: running.command, status: .interrupted))
            self.running = nil
        }
        interrupted.append(contentsOf: pending.map {
            SidekickRequestSnapshot(id: $0.id, command: $0.command, status: .interrupted)
        })
        pending.removeAll()
        return interrupted
    }
}
