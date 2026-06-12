import Foundation

public struct ComputerUsePermissionSnapshot: Codable, Equatable, Sendable {
    public let accessibilityGranted: Bool
    public let screenRecordingGranted: Bool

    public init(accessibilityGranted: Bool, screenRecordingGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
    }

    public var isReady: Bool {
        accessibilityGranted && screenRecordingGranted
    }
}

public struct ComputerUseInstalledApp: Codable, Equatable, Sendable {
    public let bundleID: String
    public let displayName: String
    public let path: String?

    public init(bundleID: String, displayName: String, path: String? = nil) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.path = path
    }
}

public struct ComputerUseWindowSummary: Codable, Equatable, Sendable {
    public let pid: Int
    public let windowID: UInt32
    public let title: String?
    public let bounds: RectSnapshot?

    public init(pid: Int, windowID: UInt32, title: String? = nil, bounds: RectSnapshot? = nil) {
        self.pid = pid
        self.windowID = windowID
        self.title = title
        self.bounds = bounds
    }
}

public enum ComputerUseSnapshotMode: String, Codable, Equatable, Sendable {
    case som
    case ax
    case vision
}

public struct ComputerUseScreenshotMetadata: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let scaleFactor: Double
    public let filePath: String?

    public init(width: Int, height: Int, scaleFactor: Double, filePath: String? = nil) {
        self.width = width
        self.height = height
        self.scaleFactor = scaleFactor
        self.filePath = filePath
    }
}

public struct ComputerUseWindowState: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let pid: Int
    public let windowID: UInt32
    public let mode: ComputerUseSnapshotMode
    public let treeMarkdown: String?
    public let screenshot: ComputerUseScreenshotMetadata?
    public let elementCount: Int

    public init(
        id: UUID = UUID(),
        pid: Int,
        windowID: UInt32,
        mode: ComputerUseSnapshotMode = .som,
        treeMarkdown: String? = nil,
        screenshot: ComputerUseScreenshotMetadata? = nil,
        elementCount: Int = 0
    ) {
        self.id = id
        self.pid = pid
        self.windowID = windowID
        self.mode = mode
        self.treeMarkdown = treeMarkdown
        self.screenshot = screenshot
        self.elementCount = elementCount
    }
}

public enum ComputerUseActionKind: String, Codable, Equatable, Sendable {
    case clickElement
    case setValue
    case typeText
    case pressKey
    case scroll
}

public struct ComputerUseElementAction: Codable, Equatable, Sendable {
    public let kind: ComputerUseActionKind
    public let pid: Int
    public let windowID: UInt32
    public let elementIndex: Int?
    public let snapshotID: UUID
    public let value: String?

    public init(
        kind: ComputerUseActionKind,
        pid: Int,
        windowID: UInt32,
        elementIndex: Int? = nil,
        snapshotID: UUID,
        value: String? = nil
    ) {
        self.kind = kind
        self.pid = pid
        self.windowID = windowID
        self.elementIndex = elementIndex
        self.snapshotID = snapshotID
        self.value = value
    }
}

public enum ComputerUseRouteDecision: Equatable, Sendable {
    case allowed
    case blocked(String)
}

public protocol ComputerUseDriving: Sendable {
    func checkPermissions(prompt: Bool) async throws -> ComputerUsePermissionSnapshot
    func listApps() async throws -> [ComputerUseInstalledApp]
    func launchApp(bundleID: String, urls: [String]) async throws -> [ComputerUseWindowSummary]
    func listWindows() async throws -> [ComputerUseWindowSummary]
    func getWindowState(pid: Int, windowID: UInt32, mode: ComputerUseSnapshotMode) async throws -> ComputerUseWindowState
    func clickElement(pid: Int, windowID: UInt32, elementIndex: Int) async throws -> ToolResult
    func setValue(pid: Int, windowID: UInt32, elementIndex: Int, value: String) async throws -> ToolResult
    func typeText(pid: Int, windowID: UInt32, text: String) async throws -> ToolResult
    func pressKey(pid: Int, windowID: UInt32?, key: String) async throws -> ToolResult
    func scroll(pid: Int, windowID: UInt32, direction: String, amount: Double) async throws -> ToolResult
}

private struct ComputerUseWindowKey: Hashable, Sendable {
    let pid: Int
    let windowID: UInt32
}

public actor ComputerUseRoutePolicy {
    private var latestSnapshots: [ComputerUseWindowKey: UUID] = [:]

    public init() {}

    public func recordSnapshot(_ state: ComputerUseWindowState) {
        latestSnapshots[ComputerUseWindowKey(pid: state.pid, windowID: state.windowID)] = state.id
    }

    public func decision(for action: ComputerUseElementAction) -> ComputerUseRouteDecision {
        let key = ComputerUseWindowKey(pid: action.pid, windowID: action.windowID)
        guard latestSnapshots[key] == action.snapshotID else {
            return .blocked("Computer action requires a fresh getWindowState snapshot for the same pid and windowID.")
        }

        switch action.kind {
        case .clickElement, .setValue:
            guard action.elementIndex != nil else {
                return .blocked("Element-indexed computer action requires elementIndex from getWindowState.")
            }
        case .typeText, .pressKey, .scroll:
            break
        }

        return .allowed
    }
}

