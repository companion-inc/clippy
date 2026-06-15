import AppKit

/// Global key-down monitor for Clippy-owned shortcuts.
///
/// The default hide/show chord is Control+Option+Command+C. It deliberately
/// adds Command to the push-to-talk modifiers so it does not fire voice capture.
@MainActor
public final class GlobalHotkeyMonitor {
    public nonisolated static let toggleVisibilityKeyCode: UInt16 = 8
    public nonisolated static let toggleVisibilityModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    public nonisolated static let toggleVisibilityLabel = "⌃⌥⌘C"

    public var onPress: (() -> Void)?

    private let keyCode: UInt16
    private let modifiers: NSEvent.ModifierFlags
    private let tracked: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init(
        keyCode: UInt16 = GlobalHotkeyMonitor.toggleVisibilityKeyCode,
        modifiers: NSEvent.ModifierFlags = GlobalHotkeyMonitor.toggleVisibilityModifiers
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    public func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let keyCode = event.keyCode
            let modifierRawValue = event.modifierFlags.rawValue
            let isRepeat = event.isARepeat
            Task { @MainActor in
                self?.handle(eventKeyCode: keyCode, modifierRawValue: modifierRawValue, isRepeat: isRepeat)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(
                eventKeyCode: event.keyCode,
                modifierRawValue: event.modifierFlags.rawValue,
                isRepeat: event.isARepeat
            )
            return event
        }
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(eventKeyCode: UInt16, modifierRawValue: NSEvent.ModifierFlags.RawValue, isRepeat: Bool) {
        guard isRepeat == false,
              Self.matches(
                keyCode: eventKeyCode,
                modifierFlags: NSEvent.ModifierFlags(rawValue: modifierRawValue),
                targetKeyCode: keyCode,
                modifiers: modifiers,
                trackedModifiers: tracked
              )
        else {
            return
        }
        onPress?()
    }

    public nonisolated static func matches(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        targetKeyCode: UInt16 = toggleVisibilityKeyCode,
        modifiers: NSEvent.ModifierFlags = toggleVisibilityModifiers,
        trackedModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]
    ) -> Bool {
        keyCode == targetKeyCode && modifierFlags.intersection(trackedModifiers) == modifiers
    }
}
