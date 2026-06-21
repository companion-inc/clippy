import AppKit

/// Fires begin/end for an exact held modifier chord anywhere on the Mac.
@MainActor
public final class ModifierHoldMonitor {
    public var onBegin: (() -> Void)?
    public var onEnd: (() -> Void)?
    public var onDoubleTap: (() -> Void)?

    public var activationDelay: TimeInterval = 0.35
    public var tapMaximumDuration: TimeInterval = 0.22
    public var doubleTapMaximumInterval: TimeInterval = 0.36

    private nonisolated static let trackedModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]

    private let required: NSEvent.ModifierFlags
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pendingStartTimestamp: TimeInterval?
    private var active = false
    private var activeStartTimestamp: TimeInterval?
    private var lastTapTimestamp: TimeInterval?
    private var activationID = 0
    private var activationTask: Task<Void, Never>?

    public init(modifiers: NSEvent.ModifierFlags, activationDelay: TimeInterval = 0.35) {
        self.required = modifiers
        self.activationDelay = max(0, activationDelay)
    }

    public func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event.modifierFlags, timestamp: event.timestamp)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event.modifierFlags, timestamp: event.timestamp)
            return event
        }
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        cancelPendingActivation()
        active = false
        activeStartTimestamp = nil
        lastTapTimestamp = nil
    }

    private func handle(_ flags: NSEvent.ModifierFlags, timestamp: TimeInterval) {
        let exactHeld = Self.matches(modifierFlags: flags, requiredModifiers: required)
        let requiredStillHeld = Self.hasRequiredModifiers(modifierFlags: flags, requiredModifiers: required)
        if exactHeld, !active, pendingStartTimestamp == nil {
            scheduleActivation(startedAt: timestamp)
        } else if !exactHeld, pendingStartTimestamp != nil {
            let startedAt = pendingStartTimestamp
            let interrupted = Self.isInterruptedByAdditionalModifiers(modifierFlags: flags, requiredModifiers: required)
            cancelPendingActivation()
            if !interrupted,
               let startedAt,
               Self.isTapDuration(start: startedAt, end: timestamp, maximum: tapMaximumDuration)
            {
                registerTap(at: timestamp)
            } else if !interrupted {
                lastTapTimestamp = nil
            }
        } else if active, !requiredStillHeld {
            let startedAt = activeStartTimestamp
            active = false
            activeStartTimestamp = nil
            onEnd?()
            if let startedAt,
               Self.isTapDuration(start: startedAt, end: timestamp, maximum: tapMaximumDuration)
            {
                registerTap(at: timestamp)
            } else {
                lastTapTimestamp = nil
            }
        }
    }

    private func scheduleActivation(startedAt timestamp: TimeInterval) {
        activationID += 1
        pendingStartTimestamp = timestamp
        let scheduledActivationID = activationID
        guard activationDelay > 0 else {
            activateIfStillPending(activationID: scheduledActivationID)
            return
        }
        activationTask?.cancel()
        let delay = activationDelay
        activationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.activateIfStillPending(activationID: scheduledActivationID)
            }
        }
    }

    private func cancelPendingActivation() {
        activationID += 1
        pendingStartTimestamp = nil
        activationTask?.cancel()
        activationTask = nil
    }

    private func activateIfStillPending(activationID scheduledActivationID: Int) {
        guard let startedAt = pendingStartTimestamp,
              !active,
              scheduledActivationID == activationID else {
            return
        }
        pendingStartTimestamp = nil
        activationTask = nil
        active = true
        activeStartTimestamp = startedAt
        onBegin?()
    }

    private func registerTap(at timestamp: TimeInterval) {
        if let previous = lastTapTimestamp,
           Self.isDoubleTap(previousTap: previous, currentTap: timestamp, maximumInterval: doubleTapMaximumInterval)
        {
            lastTapTimestamp = nil
            onDoubleTap?()
        } else {
            lastTapTimestamp = timestamp
        }
    }

    public nonisolated static func matches(
        modifierFlags: NSEvent.ModifierFlags,
        requiredModifiers: NSEvent.ModifierFlags
    ) -> Bool {
        modifierFlags.intersection(trackedModifiers) == requiredModifiers
    }

    public nonisolated static func hasRequiredModifiers(
        modifierFlags: NSEvent.ModifierFlags,
        requiredModifiers: NSEvent.ModifierFlags
    ) -> Bool {
        requiredModifiers.isSubset(of: modifierFlags.intersection(trackedModifiers))
    }

    public nonisolated static func isInterruptedByAdditionalModifiers(
        modifierFlags: NSEvent.ModifierFlags,
        requiredModifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let tracked = modifierFlags.intersection(trackedModifiers)
        return requiredModifiers.isSubset(of: tracked) && tracked != requiredModifiers
    }

    private nonisolated static func nanoseconds(for delay: TimeInterval) -> UInt64 {
        UInt64((max(0, delay) * 1_000_000_000).rounded())
    }

    public nonisolated static func isTapDuration(
        start: TimeInterval,
        end: TimeInterval,
        maximum: TimeInterval
    ) -> Bool {
        end >= start && end - start <= maximum
    }

    public nonisolated static func isDoubleTap(
        previousTap: TimeInterval,
        currentTap: TimeInterval,
        maximumInterval: TimeInterval
    ) -> Bool {
        currentTap > previousTap && currentTap - previousTap <= maximumInterval
    }
}
