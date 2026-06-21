import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum ChronicleRecordingState: String, Codable, Equatable, Sendable {
    case idle
    case recording
    case stopped
    case cancelled
}

public struct ChronicleSessionMetadata: Codable, Equatable, Sendable {
    public let id: String
    public let state: ChronicleRecordingState
    public let startedAt: Date
    public let updatedAt: Date
    public let endedAt: Date?
    public let storageRoot: String
    public let sessionDirectory: String
    public let metadataPath: String
    public let eventsPath: String
    public let framesDirectory: String
    public let eventCount: Int
    public let frameCount: Int
    public let timeLimitSeconds: Int
    public let warning: String?

    public init(
        id: String,
        state: ChronicleRecordingState,
        startedAt: Date,
        updatedAt: Date,
        endedAt: Date?,
        storageRoot: String,
        sessionDirectory: String,
        metadataPath: String,
        eventsPath: String,
        framesDirectory: String,
        eventCount: Int,
        frameCount: Int,
        timeLimitSeconds: Int,
        warning: String?
    ) {
        self.id = id
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.endedAt = endedAt
        self.storageRoot = storageRoot
        self.sessionDirectory = sessionDirectory
        self.metadataPath = metadataPath
        self.eventsPath = eventsPath
        self.framesDirectory = framesDirectory
        self.eventCount = eventCount
        self.frameCount = frameCount
        self.timeLimitSeconds = timeLimitSeconds
        self.warning = warning
    }
}

public struct ChronicleScreenshotFrame: Codable, Equatable, Sendable {
    public let path: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let screenIndex: Int
    public let screenFrame: ChronicleRect

    public init(path: String, pixelWidth: Int, pixelHeight: Int, screenIndex: Int, screenFrame: ChronicleRect) {
        self.path = path
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.screenIndex = screenIndex
        self.screenFrame = screenFrame
    }
}

public struct ChronicleRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.width)
        self.height = Double(rect.height)
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ChronicleDesktopSnapshot: Codable, Equatable, Sendable {
    public struct App: Codable, Equatable, Sendable {
        public let name: String
        public let bundleIdentifier: String?
        public let processIdentifier: Int
    }

    public struct Window: Codable, Equatable, Sendable {
        public let title: String?
        public let ownerName: String
        public let ownerProcessIdentifier: Int
        public let windowIdentifier: Int
        public let bounds: ChronicleRect
    }

    public struct Screen: Codable, Equatable, Sendable {
        public let index: Int
        public let appKitFrame: ChronicleRect
        public let displayBounds: ChronicleRect
        public let displayIdentifier: UInt32
    }

    public struct Browser: Codable, Equatable, Sendable {
        public let title: String?
        public let url: String?
    }

    public let app: App?
    public let window: Window?
    public let screen: Screen?
    public let browser: Browser?

    public init(app: App?, window: Window?, screen: Screen?, browser: Browser?) {
        self.app = app
        self.window = window
        self.screen = screen
        self.browser = browser
    }

    public init(_ snapshot: DesktopContextSnapshot) {
        self.app = snapshot.app.map {
            App(name: $0.name, bundleIdentifier: $0.bundleIdentifier, processIdentifier: $0.processIdentifier)
        }
        self.window = snapshot.window.map {
            Window(
                title: $0.title,
                ownerName: $0.ownerName,
                ownerProcessIdentifier: $0.ownerProcessIdentifier,
                windowIdentifier: $0.windowIdentifier,
                bounds: ChronicleRect($0.bounds)
            )
        }
        self.screen = snapshot.screen.map {
            Screen(
                index: $0.index,
                appKitFrame: ChronicleRect($0.appKitFrame),
                displayBounds: ChronicleRect($0.displayBounds),
                displayIdentifier: $0.displayIdentifier
            )
        }
        self.browser = snapshot.browser.map {
            Browser(title: $0.title, url: $0.url)
        }
    }
}

public struct ChronicleFocusedElementSnapshot: Codable, Equatable, Sendable {
    public let role: String?
    public let title: String?
    public let value: String?
    public let frame: ChronicleRect?
    public let isSensitive: Bool

    public init(role: String?, title: String?, value: String?, frame: ChronicleRect?, isSensitive: Bool) {
        self.role = role
        self.title = title
        self.value = value
        self.frame = frame
        self.isSensitive = isSensitive
    }
}

public struct ChronicleInputEvent: Codable, Equatable, Sendable {
    public let kind: String
    public let x: Double?
    public let y: Double?
    public let buttonNumber: Int?
    public let clickCount: Int?
    public let keyCode: Int?
    public let characters: String?
    public let modifierFlags: UInt64?
    public let scrollX: Int?
    public let scrollY: Int?

    public init(
        kind: String,
        x: Double? = nil,
        y: Double? = nil,
        buttonNumber: Int? = nil,
        clickCount: Int? = nil,
        keyCode: Int? = nil,
        characters: String? = nil,
        modifierFlags: UInt64? = nil,
        scrollX: Int? = nil,
        scrollY: Int? = nil
    ) {
        self.kind = kind
        self.x = x
        self.y = y
        self.buttonNumber = buttonNumber
        self.clickCount = clickCount
        self.keyCode = keyCode
        self.characters = characters
        self.modifierFlags = modifierFlags
        self.scrollX = scrollX
        self.scrollY = scrollY
    }
}

public struct ChronicleEvent: Codable, Equatable, Sendable {
    public let id: String
    public let sessionID: String
    public let timestamp: Date
    public let type: String
    public let reason: String?
    public let desktop: ChronicleDesktopSnapshot?
    public let focusedElement: ChronicleFocusedElementSnapshot?
    public let input: ChronicleInputEvent?
    public let screenshots: [ChronicleScreenshotFrame]
    public let message: String?

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        timestamp: Date,
        type: String,
        reason: String? = nil,
        desktop: ChronicleDesktopSnapshot? = nil,
        focusedElement: ChronicleFocusedElementSnapshot? = nil,
        input: ChronicleInputEvent? = nil,
        screenshots: [ChronicleScreenshotFrame] = [],
        message: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.type = type
        self.reason = reason
        self.desktop = desktop
        self.focusedElement = focusedElement
        self.input = input
        self.screenshots = screenshots
        self.message = message
    }
}

public protocol ChronicleScreenCapturing: Sendable {
    func captureFrame(directory: URL, frameID: String) -> [ChronicleScreenshotFrame]
}

public struct LiveChronicleScreenCapture: ChronicleScreenCapturing {
    public init() {}

    public func captureFrame(directory: URL, frameID: String) -> [ChronicleScreenshotFrame] {
        ScreenPerception.captureAllToFiles(
            directory: directory,
            fileNamePrefix: frameID,
            maxDimension: 1600,
            compression: 0.7
        ).map {
            ChronicleScreenshotFrame(
                path: $0.path,
                pixelWidth: Int($0.pixelSize.width),
                pixelHeight: Int($0.pixelSize.height),
                screenIndex: $0.screenIndex,
                screenFrame: ChronicleRect($0.screenFrame)
            )
        }
    }
}

public final class SidekickChronicleRecorder: @unchecked Sendable {
    public static let shared = SidekickChronicleRecorder()

    public static var defaultStorageRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Sidekick/Chronicle", isDirectory: true)
    }

    private let storageRoot: URL
    private let fileManager: FileManager
    private let screenCapture: any ChronicleScreenCapturing
    private let now: @Sendable () -> Date
    private let eventMonitorFactory: (@Sendable (@escaping @Sendable (ChronicleInputEvent) -> Void) throws -> ChronicleSystemEventMonitoring)?
    private let queue = DispatchQueue(label: "ai.companion.sidekick.chronicle.recorder")

    private var active: ActiveRecording?
    private var latest: ActiveRecording?

    public init(
        storageRoot: URL = SidekickChronicleRecorder.defaultStorageRoot,
        fileManager: FileManager = .default,
        screenCapture: any ChronicleScreenCapturing = LiveChronicleScreenCapture(),
        now: @escaping @Sendable () -> Date = { Date() },
        eventMonitorFactory: (@Sendable (@escaping @Sendable (ChronicleInputEvent) -> Void) throws -> ChronicleSystemEventMonitoring)? = {
            ChronicleSystemEventMonitor(eventHandler: $0)
        }
    ) {
        self.storageRoot = storageRoot
        self.fileManager = fileManager
        self.screenCapture = screenCapture
        self.now = now
        self.eventMonitorFactory = eventMonitorFactory
    }

    public func start(timeLimitSeconds: Int = 30 * 60) throws -> ChronicleSessionMetadata {
        try queue.sync {
            if let active, active.state == .recording {
                return try metadataLocked(for: active)
            }

            let start = now()
            let id = Self.sessionID(for: start)
            let directory = storageRoot.appendingPathComponent(id, isDirectory: true)
            let frames = directory.appendingPathComponent("frames", isDirectory: true)
            try fileManager.createDirectory(at: frames, withIntermediateDirectories: true)

            let recording = ActiveRecording(
                id: id,
                state: .recording,
                startedAt: start,
                updatedAt: start,
                endedAt: nil,
                storageRoot: storageRoot,
                directory: directory,
                metadataURL: directory.appendingPathComponent("session.json"),
                eventsURL: directory.appendingPathComponent("events.jsonl"),
                framesDirectory: frames,
                timeLimitSeconds: timeLimitSeconds
            )
            fileManager.createFile(atPath: recording.eventsURL.path, contents: nil)
            active = recording
            latest = recording

            appendEventLocked(
                type: "recording_started",
                reason: "event_stream_start",
                to: recording
            )
            recordSampleLocked(reason: "start", to: recording)
            startEventMonitorLocked(for: recording)
            startSampleTimerLocked(for: recording)
            try writeMetadataLocked(for: recording)
            return try metadataLocked(for: recording)
        }
    }

    public func status() throws -> ChronicleSessionMetadata? {
        try queue.sync {
            guard let recording = active ?? latest else { return nil }
            return try metadataLocked(for: recording)
        }
    }

    public func stop() throws -> ChronicleSessionMetadata {
        try queue.sync {
            guard let recording = active else {
                if let latest {
                    return try metadataLocked(for: latest)
                }
                throw ChronicleRecorderError.noActiveRecording
            }
            stopLocked(recording, state: .stopped, reason: "event_stream_stop")
            active = nil
            latest = recording
            return try metadataLocked(for: recording)
        }
    }

    public func cancel() throws -> ChronicleSessionMetadata {
        try queue.sync {
            guard let recording = active else {
                if let latest {
                    return try metadataLocked(for: latest)
                }
                throw ChronicleRecorderError.noActiveRecording
            }
            stopLocked(recording, state: .cancelled, reason: "event_stream_cancel")
            active = nil
            latest = recording
            return try metadataLocked(for: recording)
        }
    }

    private func startEventMonitorLocked(for recording: ActiveRecording) {
        guard let eventMonitorFactory else {
            recording.warning = "Input event monitoring is disabled."
            return
        }
        do {
            let monitor = try eventMonitorFactory { [weak self] input in
                self?.recordInput(input)
            }
            try monitor.start()
            recording.eventMonitor = monitor
        } catch {
            recording.warning = "Input event monitor unavailable: \(error.localizedDescription)"
            appendEventLocked(
                type: "recording_warning",
                reason: "input_monitor",
                to: recording,
                message: recording.warning
            )
        }
    }

    private func startSampleTimerLocked(for recording: ActiveRecording) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let limit = DispatchTimeInterval.seconds(max(1, recording.timeLimitSeconds))
        timer.schedule(deadline: .now() + .seconds(10), repeating: .seconds(10), leeway: .seconds(2))
        timer.setEventHandler { [weak self, weak recording] in
            guard let self, let recording, self.active === recording else { return }
            self.recordSampleLocked(reason: "timer", to: recording)
        }
        timer.resume()
        recording.sampleTimer = timer

        let limitTimer = DispatchSource.makeTimerSource(queue: queue)
        limitTimer.schedule(deadline: .now() + limit)
        limitTimer.setEventHandler { [weak self, weak recording] in
            guard let self, let recording, self.active === recording else { return }
            self.stopLocked(recording, state: .stopped, reason: "time_limit")
            self.active = nil
            self.latest = recording
        }
        limitTimer.resume()
        recording.limitTimer = limitTimer
    }

    private func recordInput(_ input: ChronicleInputEvent) {
        queue.async { [weak self] in
            guard let self, let recording = self.active, recording.state == .recording else { return }
            self.appendEventLocked(
                type: "input_event",
                reason: input.kind,
                to: recording,
                input: input
            )
            switch input.kind {
            case "left_mouse_down", "right_mouse_down", "other_mouse_down", "key_down":
                self.recordSampleLocked(reason: input.kind, to: recording)
            default:
                break
            }
        }
    }

    private func recordSampleLocked(reason: String, to recording: ActiveRecording) {
        guard recording.state == .recording else { return }
        let frameID = String(format: "frame-%06d", recording.frameCount + 1)
        let screenshots = screenCapture.captureFrame(directory: recording.framesDirectory, frameID: frameID)
        if screenshots.isEmpty == false {
            recording.frameCount += 1
        }
        let desktop = ChronicleDesktopSnapshot(DesktopContextSnapshot.capture())
        let focused = ChronicleFocusedElementSnapshot.capture()
        appendEventLocked(
            type: "screen_sample",
            reason: reason,
            to: recording,
            desktop: desktop,
            focusedElement: focused,
            screenshots: screenshots
        )
    }

    private func stopLocked(_ recording: ActiveRecording, state: ChronicleRecordingState, reason: String) {
        recording.sampleTimer?.cancel()
        recording.limitTimer?.cancel()
        recording.sampleTimer = nil
        recording.limitTimer = nil
        recording.eventMonitor?.stop()
        recording.eventMonitor = nil
        recording.state = state
        recording.endedAt = now()
        recording.updatedAt = recording.endedAt ?? now()
        appendEventLocked(type: "recording_\(state.rawValue)", reason: reason, to: recording)
        try? writeMetadataLocked(for: recording)
    }

    private func appendEventLocked(
        type: String,
        reason: String?,
        to recording: ActiveRecording,
        desktop: ChronicleDesktopSnapshot? = nil,
        focusedElement: ChronicleFocusedElementSnapshot? = nil,
        input: ChronicleInputEvent? = nil,
        screenshots: [ChronicleScreenshotFrame] = [],
        message: String? = nil
    ) {
        let event = ChronicleEvent(
            sessionID: recording.id,
            timestamp: now(),
            type: type,
            reason: reason,
            desktop: desktop,
            focusedElement: focusedElement,
            input: input,
            screenshots: screenshots,
            message: message
        )
        do {
            var data = try Self.eventEncoder.encode(event)
            data.append(0x0A)
            let handle = try FileHandle(forWritingTo: recording.eventsURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
            recording.eventCount += 1
            recording.updatedAt = event.timestamp
            try writeMetadataLocked(for: recording)
        } catch {
            recording.warning = "Could not write Chronicle event: \(error.localizedDescription)"
        }
    }

    private func metadataLocked(for recording: ActiveRecording) throws -> ChronicleSessionMetadata {
        let metadata = ChronicleSessionMetadata(
            id: recording.id,
            state: recording.state,
            startedAt: recording.startedAt,
            updatedAt: recording.updatedAt,
            endedAt: recording.endedAt,
            storageRoot: recording.storageRoot.path,
            sessionDirectory: recording.directory.path,
            metadataPath: recording.metadataURL.path,
            eventsPath: recording.eventsURL.path,
            framesDirectory: recording.framesDirectory.path,
            eventCount: recording.eventCount,
            frameCount: recording.frameCount,
            timeLimitSeconds: recording.timeLimitSeconds,
            warning: recording.warning
        )
        return metadata
    }

    private func writeMetadataLocked(for recording: ActiveRecording) throws {
        let metadata = try metadataLocked(for: recording)
        let data = try Self.prettyEncoder.encode(metadata)
        try data.write(to: recording.metadataURL, options: .atomic)
    }

    private static func sessionID(for date: Date) -> String {
        "chronicle-\(sessionIDFormatter.string(from: date))-\(UUID().uuidString.prefix(8))"
    }

    private static let sessionIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let eventEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private final class ActiveRecording {
    let id: String
    var state: ChronicleRecordingState
    let startedAt: Date
    var updatedAt: Date
    var endedAt: Date?
    let storageRoot: URL
    let directory: URL
    let metadataURL: URL
    let eventsURL: URL
    let framesDirectory: URL
    let timeLimitSeconds: Int
    var eventCount = 0
    var frameCount = 0
    var warning: String?
    var sampleTimer: DispatchSourceTimer?
    var limitTimer: DispatchSourceTimer?
    var eventMonitor: ChronicleSystemEventMonitoring?

    init(
        id: String,
        state: ChronicleRecordingState,
        startedAt: Date,
        updatedAt: Date,
        endedAt: Date?,
        storageRoot: URL,
        directory: URL,
        metadataURL: URL,
        eventsURL: URL,
        framesDirectory: URL,
        timeLimitSeconds: Int
    ) {
        self.id = id
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.endedAt = endedAt
        self.storageRoot = storageRoot
        self.directory = directory
        self.metadataURL = metadataURL
        self.eventsURL = eventsURL
        self.framesDirectory = framesDirectory
        self.timeLimitSeconds = timeLimitSeconds
    }
}

public enum ChronicleRecorderError: LocalizedError, Equatable {
    case noActiveRecording

    public var errorDescription: String? {
        switch self {
        case .noActiveRecording:
            return "No Chronicle recording is active."
        }
    }
}

private extension ChronicleFocusedElementSnapshot {
    static func capture() -> ChronicleFocusedElementSnapshot? {
        let system = AXUIElementCreateSystemWide()
        var rawFocused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &rawFocused) == .success,
              let focused = rawFocused else {
            return nil
        }
        let element = focused as! AXUIElement
        let role = stringAttribute(kAXRoleAttribute, from: element)
        let title = stringAttribute(kAXTitleAttribute, from: element) ?? stringAttribute(kAXDescriptionAttribute, from: element)
        let rawValue = stringAttribute(kAXValueAttribute, from: element)
        let sensitive = isSensitive(role: role, title: title, value: rawValue)
        let value = sensitive ? "[redacted]" : rawValue
        return ChronicleFocusedElementSnapshot(
            role: role,
            title: title,
            value: value,
            frame: frameAttribute(from: element),
            isSensitive: sensitive
        )
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else {
            return nil
        }
        if let string = value as? String {
            return string.isEmpty ? nil : string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func frameAttribute(from element: AXUIElement) -> ChronicleRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef,
              let sizeValue = sizeRef else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return ChronicleRect(x: Double(point.x), y: Double(point.y), width: Double(size.width), height: Double(size.height))
    }

    private static func isSensitive(role: String?, title: String?, value: String?) -> Bool {
        let text = [role, title, value]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return ["password", "passcode", "secret", "token", "api key", "apikey", "otp", "verification code"].contains { text.contains($0) }
    }
}
