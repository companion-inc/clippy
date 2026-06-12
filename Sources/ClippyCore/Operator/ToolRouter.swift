import Foundation

public enum ToolRoutingOutcome: Equatable, Sendable {
    case completed(ToolResult)
    case approvalRequired(ApprovalRequest)
}

public actor ToolRouter {
    private var executors: [String: any ToolExecuting] = [:]
    private let approvalPolicy: ApprovalPolicy

    public init(approvalPolicy: ApprovalPolicy = ApprovalPolicy()) {
        self.approvalPolicy = approvalPolicy
    }

    public func register(name: String, executor: any ToolExecuting) {
        executors[name] = executor
    }

    public func route(_ invocation: ToolInvocation, approved: Bool = false) async -> ToolRoutingOutcome {
        if !approved {
            switch approvalPolicy.decision(for: invocation) {
            case .allowed:
                break
            case let .requiresApproval(risk, reason):
                return .approvalRequired(ApprovalRequest(invocation: invocation, risk: risk, reason: reason))
            }
        }

        guard let executor = executors[invocation.name] else {
            return .completed(ToolResult(
                invocationID: invocation.id,
                toolName: invocation.name,
                status: .failed,
                summary: "No executor registered for \(invocation.name)."
            ))
        }

        return .completed(await executor.execute(invocation))
    }
}
