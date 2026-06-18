import AppKit

/// Fires begin/end for an exact held modifier chord anywhere on the Mac.
@MainActor
public final class ModifierHoldMonitor {
    public var onBegin: (() -> Void)?
    public var onEnd: (() -> Void)?

    private nonisolated static let trackedModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]

    private let required: NSEvent.ModifierFlags
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var active = false

    public init(modifiers: NSEvent.ModifierFlags) {
        self.required = modifiers
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
        active = false
    }

    private func handle(_ flags: NSEvent.ModifierFlags) {
        let held = Self.matches(modifierFlags: flags, requiredModifiers: required)
        if held, !active {
            active = true
            onBegin?()
        } else if !held, active {
            active = false
            onEnd?()
        }
    }

    public nonisolated static func matches(
        modifierFlags: NSEvent.ModifierFlags,
        requiredModifiers: NSEvent.ModifierFlags
    ) -> Bool {
        modifierFlags.intersection(trackedModifiers) == requiredModifiers
    }
}
