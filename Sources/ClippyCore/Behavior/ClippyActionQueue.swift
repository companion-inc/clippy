import Foundation

public actor ClippyActionQueue {
    private var pending: [ClippyAction] = []
    private var running: ClippyAction?

    public init() {}

    public var pendingCount: Int {
        pending.count
    }

    public var current: ClippyAction? {
        running
    }

    @discardableResult
    public func enqueue(_ action: ClippyAction) -> ClippyRequestSnapshot {
        pending.append(action)
        return ClippyRequestSnapshot(id: action.id, command: action.command, status: .queued)
    }

    public func startNext() -> ClippyRequestSnapshot? {
        guard running == nil, !pending.isEmpty else {
            return nil
        }
        let next = pending.removeFirst()
        running = next
        return ClippyRequestSnapshot(id: next.id, command: next.command, status: .running)
    }

    public func finishCurrent(status: ClippyRequestStatus = .complete) -> ClippyRequestSnapshot? {
        guard let running else {
            return nil
        }
        self.running = nil
        return ClippyRequestSnapshot(id: running.id, command: running.command, status: status)
    }

    public func stopCurrent() -> ClippyRequestSnapshot? {
        finishCurrent(status: .interrupted)
    }

    public func stopAll() -> [ClippyRequestSnapshot] {
        var interrupted: [ClippyRequestSnapshot] = []
        if let running {
            interrupted.append(ClippyRequestSnapshot(id: running.id, command: running.command, status: .interrupted))
            self.running = nil
        }
        interrupted.append(contentsOf: pending.map {
            ClippyRequestSnapshot(id: $0.id, command: $0.command, status: .interrupted)
        })
        pending.removeAll()
        return interrupted
    }
}
