import AppKit

@MainActor
public final class KeyboardShortcutMonitor {
    private nonisolated static let trackedModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]

    private let keyCode: UInt16
    private let modifiers: NSEvent.ModifierFlags
    private let onTrigger: () -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        onTrigger: @escaping () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.onTrigger = onTrigger
    }

    public func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
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
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
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
        onTrigger()
        return true
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
}
