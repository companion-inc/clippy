import Foundation

public enum ApprovalRisk: String, Codable, Equatable, Sendable {
    case none
    case ambiguousTarget
    case privacySensitive
    case credentialSensitive
    case accountSensitive
    case paymentSensitive
    case externalFacing
    case destructive
    case shell
}

public struct ApprovalRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let invocation: ToolInvocation
    public let risk: ApprovalRisk
    public let reason: String

    public init(
        id: UUID = UUID(),
        invocation: ToolInvocation,
        risk: ApprovalRisk,
        reason: String
    ) {
        self.id = id
        self.invocation = invocation
        self.risk = risk
        self.reason = reason
    }
}

public enum ApprovalDecision: Equatable, Sendable {
    case allowed
    case requiresApproval(ApprovalRisk, String)
}

public struct ProtectedToolPrefix: Codable, Equatable, Sendable {
    public let prefix: String
    public let risk: ApprovalRisk

    public init(prefix: String, risk: ApprovalRisk) {
        self.prefix = prefix
        self.risk = risk
    }
}

public struct ApprovalPolicy: Sendable {
    private let protectedTools: [String: ApprovalRisk]
    private let protectedPrefixes: [ProtectedToolPrefix]

    public init(
        protectedTools: [String: ApprovalRisk] = ApprovalPolicy.defaultProtectedTools,
        protectedPrefixes: [ProtectedToolPrefix] = ApprovalPolicy.defaultProtectedPrefixes
    ) {
        self.protectedTools = protectedTools
        self.protectedPrefixes = protectedPrefixes
    }

    public func decision(for invocation: ToolInvocation) -> ApprovalDecision {
        if let risk = protectedTools[invocation.name] {
            return .requiresApproval(risk, reason(for: invocation.name, risk: risk))
        }
        if let match = protectedPrefixes.first(where: { invocation.name.hasPrefix($0.prefix) }) {
            return .requiresApproval(match.risk, reason(for: invocation.name, risk: match.risk))
        }
        return .allowed
    }

    private func reason(for tool: String, risk: ApprovalRisk) -> String {
        switch risk {
        case .none:
            return "\(tool) is allowed."
        case .ambiguousTarget:
            return "\(tool) needs a concrete target before Sidekick acts."
        case .privacySensitive:
            return "\(tool) can expose private local context."
        case .credentialSensitive:
            return "\(tool) can interact with credentials or signed-in accounts."
        case .accountSensitive:
            return "\(tool) can change account, security, or privacy settings."
        case .paymentSensitive:
            return "\(tool) can purchase, trade, transfer, or move money."
        case .externalFacing:
            return "\(tool) can send, publish, purchase, or otherwise affect an outside system."
        case .destructive:
            return "\(tool) can delete, overwrite, move, or irreversibly change local data."
        case .shell:
            return "\(tool) can run local commands."
        }
    }
}

public extension ApprovalPolicy {
    static let defaultProtectedTools: [String: ApprovalRisk] = [
        "observe.camera": .privacySensitive,
        "computer.click": .ambiguousTarget,
        "computer.click_element": .ambiguousTarget,
        "computer.double_click": .ambiguousTarget,
        "computer.drag": .ambiguousTarget,
        "computer.set_value": .ambiguousTarget,
        "computer.type_text": .ambiguousTarget,
        "computer.key": .ambiguousTarget,
        "computer.press_key": .ambiguousTarget,
        "computer.hotkey": .ambiguousTarget,
        "computer.scroll": .ambiguousTarget,
        "shell.exec": .shell,
        "file.write": .destructive,
        "file.delete": .destructive,
        "browser.submit": .externalFacing,
        "message.send": .externalFacing,
        "email.send": .externalFacing,
        "payment.submit": .externalFacing,
        "purchase.submit": .paymentSensitive,
    ]

    static let defaultProtectedPrefixes: [ProtectedToolPrefix] = [
        ProtectedToolPrefix(prefix: "credential.", risk: .credentialSensitive),
        ProtectedToolPrefix(prefix: "account.", risk: .accountSensitive),
        ProtectedToolPrefix(prefix: "payment.", risk: .paymentSensitive),
        ProtectedToolPrefix(prefix: "purchase.", risk: .paymentSensitive),
        ProtectedToolPrefix(prefix: "publish.", risk: .externalFacing),
    ]
}
