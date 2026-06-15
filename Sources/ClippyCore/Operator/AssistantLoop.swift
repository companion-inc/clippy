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

    /// Callbacks for driving the character while the loop runs. `approvalHandler`
    /// resolves a protected action interactively; when nil (the default), the
    /// loop stops at the first approval request and returns it.
    public struct Hooks: Sendable {
        public var approvalHandler: (@Sendable (ApprovalRequest) async -> Bool)?
        public var onToolStarted: (@Sendable (String) -> Void)?
        public var onToolFinished: (@Sendable (String, ToolResultStatus) -> Void)?

        public init(
            approvalHandler: (@Sendable (ApprovalRequest) async -> Bool)? = nil,
            onToolStarted: (@Sendable (String) -> Void)? = nil,
            onToolFinished: (@Sendable (String, ToolResultStatus) -> Void)? = nil
        ) {
            self.approvalHandler = approvalHandler
            self.onToolStarted = onToolStarted
            self.onToolFinished = onToolFinished
        }
    }

    public func run(userText: String, maxRounds: Int = 8, hooks: Hooks = Hooks()) async -> AssistantLoopResult {
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
                hooks.onToolStarted?(invocation.name)
                switch await toolRouter.route(invocation) {
                case let .completed(result):
                    observations.append(result)
                    hooks.onToolFinished?(invocation.name, result.status)
                case let .approvalRequired(request):
                    guard let approvalHandler = hooks.approvalHandler else {
                        return AssistantLoopResult(
                            stopReason: .approvalRequired,
                            toolResults: observations,
                            approvalRequest: request
                        )
                    }
                    let approved = await approvalHandler(request)
                    guard approved else {
                        let denial = ToolResult(
                            invocationID: invocation.id,
                            toolName: invocation.name,
                            status: .failed,
                            summary: "User denied permission to run \(invocation.name)."
                        )
                        observations.append(denial)
                        hooks.onToolFinished?(invocation.name, .failed)
                        continue
                    }
                    if case let .completed(result) = await toolRouter.route(invocation, approved: true) {
                        observations.append(result)
                        hooks.onToolFinished?(invocation.name, result.status)
                    }
                }
            }
        }

        return AssistantLoopResult(
            stopReason: .maxRounds,
            toolResults: observations
        )
    }
}
