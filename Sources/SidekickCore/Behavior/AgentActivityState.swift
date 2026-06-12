import Foundation

public enum SidekickAgentID: String, CaseIterable, Codable, Equatable, Sendable {
    case clippy
    case claudeCode = "claude-code"
    case codex

    public var displayName: String {
        switch self {
        case .clippy:
            return "Clippy"
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }
}

public enum AgentActivityState: String, CaseIterable, Codable, Equatable, Sendable {
    case idle
    case thinking
    case working
    case notification
    case attention
    case error
    case sweeping
    case carrying
    case juggling
    case sleeping

    public var mascotState: MascotState {
        switch self {
        case .idle:
            return .idle
        case .thinking:
            return .thinking
        case .working, .juggling, .carrying:
            return .computerControl
        case .notification:
            return .waitingApproval
        case .attention:
            return .done
        case .error:
            return .error
        case .sweeping:
            return .reading
        case .sleeping:
            return .idle
        }
    }

    public var priority: Int {
        switch self {
        case .error:
            return 8
        case .notification:
            return 7
        case .sweeping:
            return 6
        case .attention:
            return 5
        case .carrying, .juggling:
            return 4
        case .working:
            return 3
        case .thinking:
            return 2
        case .idle:
            return 1
        case .sleeping:
            return 0
        }
    }
}

public enum AgentLifecycleEvent: String, CaseIterable, Codable, Equatable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
    case notification = "Notification"
    case elicitation = "Elicitation"
    case permissionRequest = "PermissionRequest"
    case worktreeCreate = "WorktreeCreate"
    case codexSessionMeta = "session_meta"
    case codexTaskStarted = "event_msg:task_started"
    case codexUserMessage = "event_msg:user_message"
    case codexGuardianAssessment = "event_msg:guardian_assessment"
    case codexExecCommandEnd = "event_msg:exec_command_end"
    case codexPatchApplyEnd = "event_msg:patch_apply_end"
    case codexCustomToolCallOutput = "event_msg:custom_tool_call_output"
    case codexFunctionCall = "response_item:function_call"
    case codexCustomToolCall = "response_item:custom_tool_call"
    case codexWebSearchCall = "response_item:web_search_call"
    case codexTaskComplete = "event_msg:task_complete"
    case codexContextCompacted = "event_msg:context_compacted"
    case codexTurnAborted = "event_msg:turn_aborted"

    public init?(rawEvent: String) {
        self.init(rawValue: rawEvent)
    }
}

public struct AgentActivityEvent: Codable, Equatable, Sendable {
    public let agentID: SidekickAgentID
    public let sessionID: String
    public let lifecycleEvent: AgentLifecycleEvent
    public let title: String?

    public init(
        agentID: SidekickAgentID,
        sessionID: String,
        lifecycleEvent: AgentLifecycleEvent,
        title: String? = nil
    ) {
        self.agentID = agentID
        self.sessionID = sessionID
        self.lifecycleEvent = lifecycleEvent
        self.title = title
    }
}

public struct AgentActivitySession: Codable, Equatable, Sendable {
    public let id: String
    public let agentID: SidekickAgentID
    public var state: AgentActivityState
    public var title: String?
    public var updatedAt: Date
    public var subagentCount: Int
    public var turnUsedTools: Bool

    public init(
        id: String,
        agentID: SidekickAgentID,
        state: AgentActivityState,
        title: String? = nil,
        updatedAt: Date = Date(),
        subagentCount: Int = 0,
        turnUsedTools: Bool = false
    ) {
        self.id = id
        self.agentID = agentID
        self.state = state
        self.title = title
        self.updatedAt = updatedAt
        self.subagentCount = subagentCount
        self.turnUsedTools = turnUsedTools
    }
}

public enum AgentStateMapper {
    public static func state(
        for event: AgentLifecycleEvent,
        agentID: SidekickAgentID,
        turnUsedTools: Bool = false
    ) -> AgentActivityState? {
        switch agentID {
        case .clippy:
            return clippyState(for: event, turnUsedTools: turnUsedTools)
        case .claudeCode:
            return claudeCodeState(for: event)
        case .codex:
            return codexState(for: event, turnUsedTools: turnUsedTools)
        }
    }

    private static func clippyState(
        for event: AgentLifecycleEvent,
        turnUsedTools: Bool
    ) -> AgentActivityState? {
        switch event {
        case .sessionStart, .sessionEnd, .codexSessionMeta, .codexTurnAborted:
            return .idle
        case .userPromptSubmit, .codexTaskStarted, .codexUserMessage:
            return .thinking
        case .preToolUse, .postToolUse, .codexGuardianAssessment, .codexExecCommandEnd,
             .codexPatchApplyEnd, .codexCustomToolCallOutput, .codexFunctionCall,
             .codexCustomToolCall, .codexWebSearchCall:
            return .working
        case .permissionRequest, .notification, .elicitation:
            return .notification
        case .postToolUseFailure, .stopFailure:
            return .error
        case .stop, .postCompact, .codexTaskComplete:
            return turnUsedTools ? .attention : .idle
        case .preCompact, .codexContextCompacted:
            return .sweeping
        case .worktreeCreate:
            return .carrying
        case .subagentStart:
            return .juggling
        case .subagentStop:
            return .working
        }
    }

    private static func claudeCodeState(for event: AgentLifecycleEvent) -> AgentActivityState? {
        switch event {
        case .sessionStart:
            return .idle
        case .sessionEnd:
            return .sleeping
        case .userPromptSubmit:
            return .thinking
        case .preToolUse, .postToolUse:
            return .working
        case .postToolUseFailure, .stopFailure:
            return .error
        case .stop, .postCompact:
            return .attention
        case .subagentStart:
            return .juggling
        case .subagentStop:
            return .working
        case .preCompact:
            return .sweeping
        case .notification, .elicitation, .permissionRequest:
            return .notification
        case .worktreeCreate:
            return .carrying
        default:
            return nil
        }
    }

    private static func codexState(
        for event: AgentLifecycleEvent,
        turnUsedTools: Bool
    ) -> AgentActivityState? {
        switch event {
        case .sessionStart, .codexSessionMeta, .codexTurnAborted:
            return .idle
        case .userPromptSubmit, .codexTaskStarted, .codexUserMessage:
            return .thinking
        case .preToolUse, .postToolUse, .codexGuardianAssessment, .codexExecCommandEnd,
             .codexPatchApplyEnd, .codexCustomToolCallOutput, .codexFunctionCall,
             .codexCustomToolCall, .codexWebSearchCall:
            return .working
        case .permissionRequest, .notification:
            return .notification
        case .postToolUseFailure, .stopFailure:
            return .error
        case .stop, .codexTaskComplete:
            return turnUsedTools ? .attention : .idle
        case .codexContextCompacted, .preCompact:
            return .sweeping
        default:
            return nil
        }
    }
}

public struct AgentSessionStore: Equatable, Sendable {
    public private(set) var sessions: [String: AgentActivitySession]

    public init(sessions: [String: AgentActivitySession] = [:]) {
        self.sessions = sessions
    }

    public var visibleState: AgentActivityState {
        sessions.values.max { lhs, rhs in
            if lhs.state.priority == rhs.state.priority {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.state.priority < rhs.state.priority
        }?.state ?? .idle
    }

    @discardableResult
    public mutating func apply(
        _ event: AgentActivityEvent,
        now: Date = Date()
    ) -> AgentActivityState {
        let key = Self.sessionKey(agentID: event.agentID, sessionID: event.sessionID)
        if event.lifecycleEvent == .sessionEnd {
            sessions.removeValue(forKey: key)
            return visibleState
        }

        var session = sessions[key] ?? AgentActivitySession(
            id: event.sessionID,
            agentID: event.agentID,
            state: .idle,
            title: event.title,
            updatedAt: now
        )
        if let title = event.title, !title.isEmpty {
            session.title = title
        }
        session.updatedAt = now

        switch event.lifecycleEvent {
        case .userPromptSubmit, .codexTaskStarted, .codexUserMessage:
            session.turnUsedTools = false
        case .preToolUse, .postToolUse, .codexGuardianAssessment, .codexExecCommandEnd,
             .codexPatchApplyEnd, .codexCustomToolCallOutput, .codexFunctionCall,
             .codexCustomToolCall, .codexWebSearchCall:
            session.turnUsedTools = true
        case .subagentStart:
            session.subagentCount += 1
            session.turnUsedTools = true
        case .subagentStop:
            session.subagentCount = max(0, session.subagentCount - 1)
        default:
            break
        }

        let turnUsedTools = session.turnUsedTools
        if let mapped = AgentStateMapper.state(
            for: event.lifecycleEvent,
            agentID: event.agentID,
            turnUsedTools: turnUsedTools
        ) {
            session.state = mapped
        }
        if event.lifecycleEvent == .stop || event.lifecycleEvent == .codexTaskComplete {
            session.turnUsedTools = false
        }
        sessions[key] = session
        return visibleState
    }

    public static func sessionKey(agentID: SidekickAgentID, sessionID: String) -> String {
        "\(agentID.rawValue):\(sessionID)"
    }
}
