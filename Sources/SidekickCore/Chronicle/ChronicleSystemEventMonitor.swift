import CoreGraphics
import Foundation

public protocol ChronicleSystemEventMonitoring: AnyObject, Sendable {
    func start() throws
    func stop()
}

public final class ChronicleSystemEventMonitor: ChronicleSystemEventMonitoring, @unchecked Sendable {
    private let eventHandler: @Sendable (ChronicleInputEvent) -> Void
    private let startSemaphore = DispatchSemaphore(value: 0)
    private var startError: Error?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    public init(eventHandler: @escaping @Sendable (ChronicleInputEvent) -> Void) {
        self.eventHandler = eventHandler
    }

    public func start() throws {
        let thread = Thread { [weak self] in
            self?.runEventTap()
        }
        thread.name = "Sidekick Chronicle Event Monitor"
        self.thread = thread
        thread.start()
        startSemaphore.wait()
        if let startError {
            throw startError
        }
    }

    public func stop() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self else { return }
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
                CFMachPortInvalidate(eventTap)
            }
            if let source = runLoopSource {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
            }
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func runEventTap() {
        let mask =
            eventMask(.leftMouseDown)
            | eventMask(.rightMouseDown)
            | eventMask(.otherMouseDown)
            | eventMask(.leftMouseDragged)
            | eventMask(.rightMouseDragged)
            | eventMask(.otherMouseDragged)
            | eventMask(.keyDown)
            | eventMask(.flagsChanged)
            | eventMask(.scrollWheel)

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            startError = ChronicleSystemEventMonitorError.eventTapUnavailable
            startSemaphore.signal()
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        let currentRunLoop = CFRunLoopGetCurrent()
        runLoop = currentRunLoop
        CFRunLoopAddSource(currentRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        startSemaphore.signal()
        CFRunLoopRun()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        guard let input = ChronicleInputEvent(type: type, event: event) else { return }
        eventHandler(input)
    }

    private static func eventMask(_ type: CGEventType) -> UInt64 {
        1 << UInt64(type.rawValue)
    }

    private func eventMask(_ type: CGEventType) -> UInt64 {
        Self.eventMask(type)
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<ChronicleSystemEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handle(type: type, event: event)
    return Unmanaged.passUnretained(event)
}

public enum ChronicleSystemEventMonitorError: LocalizedError, Equatable {
    case eventTapUnavailable

    public var errorDescription: String? {
        switch self {
        case .eventTapUnavailable:
            return "macOS did not allow Chronicle to create a listen-only input event tap."
        }
    }
}

private extension ChronicleInputEvent {
    init?(type: CGEventType, event: CGEvent) {
        let flags = event.flags.rawValue
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let point = event.location
            self.init(
                kind: type.chronicleKind,
                x: Double(point.x),
                y: Double(point.y),
                buttonNumber: Int(event.getIntegerValueField(.mouseEventButtonNumber)),
                clickCount: Int(event.getIntegerValueField(.mouseEventClickState)),
                modifierFlags: flags
            )
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let point = event.location
            self.init(
                kind: type.chronicleKind,
                x: Double(point.x),
                y: Double(point.y),
                buttonNumber: Int(event.getIntegerValueField(.mouseEventButtonNumber)),
                modifierFlags: flags
            )
        case .keyDown:
            self.init(
                kind: "key_down",
                keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                characters: Self.printableCharacters(from: event),
                modifierFlags: flags
            )
        case .flagsChanged:
            self.init(kind: "flags_changed", modifierFlags: flags)
        case .scrollWheel:
            self.init(
                kind: "scroll_wheel",
                modifierFlags: flags,
                scrollX: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                scrollY: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            )
        default:
            return nil
        }
    }

    private static func printableCharacters(from event: CGEvent) -> String? {
        var actualLength = 0
        var chars = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(
            maxStringLength: chars.count,
            actualStringLength: &actualLength,
            unicodeString: &chars
        )
        guard actualLength > 0 else { return nil }
        let scalars = chars.prefix(actualLength).compactMap { UnicodeScalar($0) }
        let text = String(String.UnicodeScalarView(scalars))
        guard text.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return text.isEmpty ? nil : text
    }
}

private extension CGEventType {
    var chronicleKind: String {
        switch self {
        case .leftMouseDown: return "left_mouse_down"
        case .rightMouseDown: return "right_mouse_down"
        case .otherMouseDown: return "other_mouse_down"
        case .leftMouseDragged: return "left_mouse_dragged"
        case .rightMouseDragged: return "right_mouse_dragged"
        case .otherMouseDragged: return "other_mouse_dragged"
        default: return "event_\(rawValue)"
        }
    }
}
