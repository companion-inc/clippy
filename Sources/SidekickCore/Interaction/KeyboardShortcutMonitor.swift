import AppKit

@MainActor
public final class KeyboardShortcutMonitor {
    public nonisolated static let defaultActivationDelay: TimeInterval = 0.24

    private nonisolated static let trackedModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]

    private let keyCode: UInt16
    private let modifiers: NSEvent.ModifierFlags
    private let activationDelay: TimeInterval
    private let onTrigger: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pendingKeyCode: UInt16?
    private var activationID = 0
    private var activationTask: Task<Void, Never>?

    public init(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        activationDelay: TimeInterval = KeyboardShortcutMonitor.defaultActivationDelay,
        onTrigger: @escaping () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.activationDelay = max(0, activationDelay)
        self.onTrigger = onTrigger
    }

    public func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.handle(event) else {
                return event
            }
            return nil
        }
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        cancelPendingActivation()
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            if pendingKeyCode == event.keyCode {
                cancelPendingActivation()
            }
            return false
        case .flagsChanged:
            if let pendingKeyCode,
               !Self.matches(
                keyCode: pendingKeyCode,
                modifierFlags: event.modifierFlags,
                requiredKeyCode: keyCode,
                requiredModifiers: modifiers
               )
            {
                cancelPendingActivation()
            }
            return false
        default:
            return false
        }
    }

    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.isARepeat == false,
              Self.matches(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                requiredKeyCode: keyCode,
                requiredModifiers: modifiers
              )
        else {
            return false
        }
        pendingKeyCode = event.keyCode
        scheduleActivation()
        return true
    }

    private func scheduleActivation() {
        activationID += 1
        let scheduledActivationID = activationID
        guard activationDelay > 0 else {
            triggerIfStillPending(activationID: scheduledActivationID)
            return
        }
        activationTask?.cancel()
        let delay = activationDelay
        activationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.triggerIfStillPending(activationID: scheduledActivationID)
            }
        }
    }

    private func cancelPendingActivation() {
        activationID += 1
        pendingKeyCode = nil
        activationTask?.cancel()
        activationTask = nil
    }

    private func triggerIfStillPending(activationID scheduledActivationID: Int) {
        guard pendingKeyCode != nil, scheduledActivationID == activationID else {
            return
        }
        pendingKeyCode = nil
        activationTask = nil
        onTrigger()
    }

    public nonisolated static func matches(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        requiredKeyCode: UInt16,
        requiredModifiers: NSEvent.ModifierFlags
    ) -> Bool {
        keyCode == requiredKeyCode
            && modifierFlags.intersection(trackedModifiers) == requiredModifiers
    }

    public nonisolated static func hasMetActivationDelay(
        start: TimeInterval,
        end: TimeInterval,
        delay: TimeInterval = defaultActivationDelay
    ) -> Bool {
        guard end >= start else { return false }
        let requiredDelay = max(0, delay)
        let elapsed = end - start
        return elapsed >= requiredDelay || abs(elapsed - requiredDelay) <= 0.000_001
    }

    private nonisolated static func nanoseconds(for delay: TimeInterval) -> UInt64 {
        UInt64((max(0, delay) * 1_000_000_000).rounded())
    }
}
