import AppKit
import Carbon.HIToolbox

/// System hotkey for Clippy-owned shortcuts.
///
/// The default hide/show chord is Control+Option+Command+C. It deliberately
/// adds Command to the push-to-talk modifiers so it does not fire voice capture.
@MainActor
public final class GlobalHotkeyMonitor {
    public nonisolated static let toggleVisibilityKeyCode: UInt16 = 8
    public nonisolated static let toggleVisibilityModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
    public nonisolated static let toggleVisibilityLabel = "⌃⌥⌘C"
    private nonisolated static let hotKeySignature = OSType(
        UInt32(UInt8(ascii: "C")) << 24
            | UInt32(UInt8(ascii: "L")) << 16
            | UInt32(UInt8(ascii: "P")) << 8
            | UInt32(UInt8(ascii: "Y"))
    )

    public var onPress: (() -> Void)?

    private let keyCode: UInt16
    private let modifiers: NSEvent.ModifierFlags
    private let tracked: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
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
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    public func start() {
        stop()
        if startSystemHotkey() {
            return
        }
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
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func startSystemHotkey() -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == GlobalHotkeyMonitor.hotKeySignature
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    monitor.fireSystemHotkey(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            eventHandlerRef = nil
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: UInt32(keyCode))
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            Self.carbonModifierMask(for: modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
            eventHandlerRef = nil
            hotKeyRef = nil
            return false
        }
        return true
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

    private func fireSystemHotkey(id: UInt32) {
        guard id == UInt32(keyCode) else { return }
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

    public nonisolated static func carbonModifierMask(for modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        if modifiers.contains(.option) { mask |= UInt32(optionKey) }
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }
}
