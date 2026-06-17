import AppKit

/// Fires begin/end when a held modifier chord (default ⌃⌥) is pressed anywhere —
/// Clippy's push-to-talk trigger.
///
/// Uses `NSEvent` flags-changed monitors. The **global** monitor (events from other
/// apps) requires Accessibility / Input Monitoring permission; without it, PTT only
/// fires while Clippy itself is focused (the local monitor).
@MainActor
public final class PushToTalkMonitor {
    public var onBegin: (() -> Void)?
    public var onEnd: (() -> Void)?

    private let required: NSEvent.ModifierFlags
    private let tracked: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var active = false

    public init(modifiers: NSEvent.ModifierFlags = [.control, .option]) {
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
        let held = flags.intersection(tracked) == required
        if held, !active {
            active = true
            onBegin?()
        } else if !held, active {
            active = false
            onEnd?()
        }
    }
}
