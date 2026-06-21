import AppKit

/// Fires begin/end when a held modifier chord (default ⌃⌥) is pressed anywhere —
/// Sidekick's push-to-talk trigger.
///
/// Uses `NSEvent` flags-changed monitors. The **global** monitor (events from other
/// apps) requires Accessibility / Input Monitoring permission; without it, PTT only
/// fires while Sidekick itself is focused (the local monitor).
@MainActor
public final class PushToTalkMonitor {
    public nonisolated static let defaultActivationDelay: TimeInterval = 0.24

    public var onBegin: (() -> Void)?
    public var onEnd: (() -> Void)?

    private let required: NSEvent.ModifierFlags
    private let activationDelay: TimeInterval
    private nonisolated static let tracked: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var held = false
    private var active = false
    private var activationID = 0
    private var activationTask: Task<Void, Never>?

    public init(
        modifiers: NSEvent.ModifierFlags = [.control, .option],
        activationDelay: TimeInterval = PushToTalkMonitor.defaultActivationDelay
    ) {
        self.required = modifiers
        self.activationDelay = max(0, activationDelay)
    }

    public func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event.modifierFlags)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event.modifierFlags)
            return event
        }
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        held = false
        active = false
        cancelPendingActivation()
    }

    private func handle(_ flags: NSEvent.ModifierFlags) {
        let isRequiredChordHeld = Self.matches(modifierFlags: flags, requiredModifiers: required)
        if isRequiredChordHeld, !held {
            held = true
            scheduleActivation()
        } else if !isRequiredChordHeld, held {
            held = false
            cancelPendingActivation()
            if active {
                active = false
                onEnd?()
            }
        }
    }

    private func scheduleActivation() {
        activationID += 1
        let scheduledActivationID = activationID
        guard activationDelay > 0 else {
            activateIfStillHeld(activationID: scheduledActivationID)
            return
        }
        activationTask?.cancel()
        let delay = activationDelay
        activationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.activateIfStillHeld(activationID: scheduledActivationID)
            }
        }
    }

    private func cancelPendingActivation() {
        activationID += 1
        activationTask?.cancel()
        activationTask = nil
    }

    private func activateIfStillHeld(activationID scheduledActivationID: Int) {
        guard held, !active, scheduledActivationID == activationID else {
            return
        }
        activationTask = nil
        active = true
        onBegin?()
    }

    public nonisolated static func matches(
        modifierFlags: NSEvent.ModifierFlags,
        requiredModifiers: NSEvent.ModifierFlags
    ) -> Bool {
        modifierFlags.intersection(tracked) == requiredModifiers
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
