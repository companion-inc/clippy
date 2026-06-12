import Foundation

public actor MascotActionQueue {
    private var pending: [MascotAction] = []
    private var running: MascotAction?

    public init() {}

    public var pendingCount: Int {
        pending.count
    }

    public var current: MascotAction? {
        running
    }

    @discardableResult
    public func enqueue(_ action: MascotAction) -> MascotRequestSnapshot {
        pending.append(action)
        return MascotRequestSnapshot(id: action.id, command: action.command, status: .queued)
    }

    public func startNext() -> MascotRequestSnapshot? {
        guard running == nil, !pending.isEmpty else {
            return nil
        }
        let next = pending.removeFirst()
        running = next
        return MascotRequestSnapshot(id: next.id, command: next.command, status: .running)
    }

    public func finishCurrent(status: MascotRequestStatus = .complete) -> MascotRequestSnapshot? {
        guard let running else {
            return nil
        }
        self.running = nil
        return MascotRequestSnapshot(id: running.id, command: running.command, status: status)
    }

    public func stopCurrent() -> MascotRequestSnapshot? {
        finishCurrent(status: .interrupted)
    }

    public func stopAll() -> [MascotRequestSnapshot] {
        var interrupted: [MascotRequestSnapshot] = []
        if let running {
            interrupted.append(MascotRequestSnapshot(id: running.id, command: running.command, status: .interrupted))
            self.running = nil
        }
        interrupted.append(contentsOf: pending.map {
            MascotRequestSnapshot(id: $0.id, command: $0.command, status: .interrupted)
        })
        pending.removeAll()
        return interrupted
    }
}
