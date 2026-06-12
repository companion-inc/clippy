import Foundation

public struct AssistantTurnRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let inputMode: AssistantInputMode
    public let rawText: String
    public let interpretedTask: String
    public let context: DesktopTaskContext
    public let preferredResponseMode: AssistantResponseMode
    public let requiresApprovalBeforeExternalAction: Bool
    public let observations: [ToolResult]

    public init(
        id: UUID = UUID(),
        inputMode: AssistantInputMode = .text,
        rawText: String,
        interpretedTask: String? = nil,
        context: DesktopTaskContext = DesktopTaskContext(),
        preferredResponseMode: AssistantResponseMode = .automatic,
        requiresApprovalBeforeExternalAction: Bool = true,
        observations: [ToolResult] = []
    ) {
        self.id = id
        self.inputMode = inputMode
        self.rawText = rawText
        self.interpretedTask = interpretedTask ?? rawText
        self.context = context
        self.preferredResponseMode = preferredResponseMode
        self.requiresApprovalBeforeExternalAction = requiresApprovalBeforeExternalAction
        self.observations = observations
    }

    public init(task: DesktopTaskRequest, observations: [ToolResult] = []) {
        self.init(
            id: task.id,
            inputMode: task.inputMode,
            rawText: task.rawText,
            interpretedTask: task.interpretedTask,
            context: task.context,
            preferredResponseMode: task.preferredResponseMode,
            requiresApprovalBeforeExternalAction: task.requiresApprovalBeforeExternalAction,
            observations: observations
        )
    }
}

public struct AssistantTurnResponse: Codable, Equatable, Sendable {
    public let finalText: String?
    public let toolCalls: [ToolInvocation]

    public init(finalText: String? = nil, toolCalls: [ToolInvocation] = []) {
        self.finalText = finalText
        self.toolCalls = toolCalls
    }
}

public protocol AssistantModelClient: Sendable {
    func nextTurn(_ request: AssistantTurnRequest) async throws -> AssistantTurnResponse
}

public enum AssistantLoopStopReason: String, Codable, Equatable, Sendable {
    case final
    case approvalRequired
    case maxRounds
    case modelError
}

public struct AssistantLoopResult: Codable, Equatable, Sendable {
    public let stopReason: AssistantLoopStopReason
    public let finalText: String?
    public let toolResults: [ToolResult]
    public let approvalRequest: ApprovalRequest?

    public init(
        stopReason: AssistantLoopStopReason,
        finalText: String? = nil,
        toolResults: [ToolResult] = [],
        approvalRequest: ApprovalRequest? = nil
    ) {
        self.stopReason = stopReason
        self.finalText = finalText
        self.toolResults = toolResults
        self.approvalRequest = approvalRequest
    }
}

public actor AssistantLoop {
    private let modelClient: any AssistantModelClient
    private let toolRouter: ToolRouter

    public init(modelClient: any AssistantModelClient, toolRouter: ToolRouter) {
        self.modelClient = modelClient
        self.toolRouter = toolRouter
    }

    public func run(userText: String, maxRounds: Int = 8) async -> AssistantLoopResult {
        var observations: [ToolResult] = []

        for _ in 0..<maxRounds {
            let response: AssistantTurnResponse
            do {
                response = try await modelClient.nextTurn(AssistantTurnRequest(rawText: userText, observations: observations))
            } catch {
                return AssistantLoopResult(
                    stopReason: .modelError,
                    finalText: error.localizedDescription,
                    toolResults: observations
                )
            }

            if let finalText = response.finalText, response.toolCalls.isEmpty {
                return AssistantLoopResult(
                    stopReason: .final,
                    finalText: finalText,
                    toolResults: observations
                )
            }

            for invocation in response.toolCalls {
                switch await toolRouter.route(invocation) {
                case let .completed(result):
                    observations.append(result)
                case let .approvalRequired(request):
                    return AssistantLoopResult(
                        stopReason: .approvalRequired,
                        toolResults: observations,
                        approvalRequest: request
                    )
                }
            }
        }

        return AssistantLoopResult(
            stopReason: .maxRounds,
            toolResults: observations
        )
    }
}
