import AppKit

/// Fires begin/end for an exact held modifier chord anywhere on the Mac.
@MainActor
public final class ModifierHoldMonitor {
    public var onBegin: (() -> Void)?
    public var onEnd: (() -> Void)?
    public var onDoubleTap: (() -> Void)?

    public var tapMaximumDuration: TimeInterval = 0.22
    public var doubleTapMaximumInterval: TimeInterval = 0.36

    private nonisolated static let trackedModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]

    private let required: NSEvent.ModifierFlags
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var active = false
    private var activeStartTimestamp: TimeInterval?
    private var lastTapTimestamp: TimeInterval?

    public init(modifiers: NSEvent.ModifierFlags) {
        self.required = modifiers
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
        active = false
        activeStartTimestamp = nil
        lastTapTimestamp = nil
    }

    private func handle(_ flags: NSEvent.ModifierFlags, timestamp: TimeInterval) {
        let held = Self.matches(modifierFlags: flags, requiredModifiers: required)
        if held, !active {
            active = true
            activeStartTimestamp = timestamp
            onBegin?()
        } else if !held, active {
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
