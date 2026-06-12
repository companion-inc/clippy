import Foundation

public struct ToolInvocation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let arguments: [String: ToolValue]

    public init(
        id: UUID = UUID(),
        name: String,
        arguments: [String: ToolValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public enum ToolResultStatus: String, Codable, Equatable, Sendable {
    case succeeded
    case failed
    case approvalRequired
}

public struct ToolResult: Codable, Equatable, Sendable {
    public let invocationID: UUID
    public let toolName: String
    public let status: ToolResultStatus
    public let summary: String
    public let payload: ToolValue

    public init(
        invocationID: UUID,
        toolName: String,
        status: ToolResultStatus,
        summary: String,
        payload: ToolValue = .null
    ) {
        self.invocationID = invocationID
        self.toolName = toolName
        self.status = status
        self.summary = summary
        self.payload = payload
    }
}

public protocol ToolExecuting: Sendable {
    func execute(_ invocation: ToolInvocation) async -> ToolResult
}

public struct ClosureToolExecutor: ToolExecuting {
    private let handler: @Sendable (ToolInvocation) async -> ToolResult

    public init(handler: @escaping @Sendable (ToolInvocation) async -> ToolResult) {
        self.handler = handler
    }

    public func execute(_ invocation: ToolInvocation) async -> ToolResult {
        await handler(invocation)
    }
}
