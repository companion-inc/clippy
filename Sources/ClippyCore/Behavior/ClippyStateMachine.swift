import Foundation

public enum ClippyRuntimeEvent: Equatable, Sendable {
    case commandStarted(ClippyCommand)
    case commandFinished(ClippyCommand, ClippyRequestStatus)
    case voice(VoiceEvent)
    case toolStarted(String)
    case toolFinished(String, ToolResultStatus)
    case approvalRequested(ApprovalRequest)
    case approvalResolved(approved: Bool)
}

public struct ClippyStateSnapshot: Equatable, Sendable {
    public let state: ClippyState
    public let lastMessage: String?
    public let awaitingApproval: ApprovalRequest?

    public init(
        state: ClippyState,
        lastMessage: String? = nil,
        awaitingApproval: ApprovalRequest? = nil
    ) {
        self.state = state
        self.lastMessage = lastMessage
        self.awaitingApproval = awaitingApproval
    }
}

public struct ClippyStateMachine: Sendable {
    private var snapshot: ClippyStateSnapshot

    public init(initialState: ClippyState = .hidden) {
        self.snapshot = ClippyStateSnapshot(state: initialState)
    }

    public var current: ClippyStateSnapshot {
        snapshot
    }

    @discardableResult
    public mutating func apply(_ event: ClippyRuntimeEvent) -> ClippyStateSnapshot {
        switch event {
        case let .commandStarted(command):
            snapshot = snapshot.replacing(state: state(for: command), message: nil, approval: snapshot.awaitingApproval)
        case let .commandFinished(command, status):
            snapshot = snapshot.replacing(state: stateAfter(command: command, status: status), message: nil, approval: nil)
        case let .voice(event):
            snapshot = snapshot.replacing(
                state: VoiceEventRouter.clippyState(for: event) ?? snapshot.state,
                message: message(for: event),
                approval: snapshot.awaitingApproval
            )
        case let .toolStarted(name):
            snapshot = snapshot.replacing(state: state(forToolName: name), message: nil, approval: nil)
        case let .toolFinished(_, status):
            snapshot = snapshot.replacing(state: status == .succeeded ? .done : .blocked, message: nil, approval: nil)
        case let .approvalRequested(request):
            snapshot = snapshot.replacing(state: .waitingApproval, message: request.reason, approval: request)
        case let .approvalResolved(approved):
            snapshot = snapshot.replacing(state: approved ? .thinking : .idle, message: nil, approval: nil)
        }
        return snapshot
    }

    private func state(for command: ClippyCommand) -> ClippyState {
        switch command {
        case .show:
            return .showing
        case .hide:
            return .hidden
        case .play, .gestureAt, .moveTo:
            return .computerControl
        case .speak:
            return .speaking
        case .think:
            return .thinking
        case let .setState(state):
            return state
        case .stopCurrent, .stopAll:
            return .idle
        }
    }

    private func stateAfter(command: ClippyCommand, status: ClippyRequestStatus) -> ClippyState {
        guard status == .complete else {
            return status == .failed ? .blocked : .idle
        }
        switch command {
        case .hide:
            return .hidden
        case let .setState(state):
            return state
        default:
            return .idle
        }
    }

    private func state(forToolName name: String) -> ClippyState {
        if name.hasPrefix("observe.screen") || name.hasPrefix("observe.ui_tree") {
            return .screenVision
        }
        if name.hasPrefix("observe.camera") {
            return .cameraVision
        }
        if name.hasPrefix("file.read") {
            return .reading
        }
        if name.hasPrefix("browser.") || name.hasPrefix("app.") {
            return .searching
        }
        if name.hasPrefix("file.write") || name.hasPrefix("computer.type_text") || name.hasPrefix("message.") || name.hasPrefix("email.") {
            return .writing
        }
        if name.hasPrefix("computer.") || name.hasPrefix("shell.") {
            return .computerControl
        }
        return .thinking
    }

    private func message(for event: VoiceEvent) -> String? {
        switch event {
        case let .transcriptInterim(text), let .transcriptFinal(text), let .failed(text):
            return text
        default:
            return nil
        }
    }
}

private extension ClippyStateSnapshot {
    func replacing(
        state: ClippyState,
        message: String?,
        approval: ApprovalRequest?
    ) -> ClippyStateSnapshot {
        ClippyStateSnapshot(state: state, lastMessage: message, awaitingApproval: approval)
    }
}
