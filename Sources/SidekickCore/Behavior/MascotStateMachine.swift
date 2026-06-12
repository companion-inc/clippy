import Foundation

public enum MascotRuntimeEvent: Equatable, Sendable {
    case commandStarted(MascotCommand)
    case commandFinished(MascotCommand, MascotRequestStatus)
    case voice(VoiceEvent)
    case toolStarted(String)
    case toolFinished(String, ToolResultStatus)
    case approvalRequested(ApprovalRequest)
    case approvalResolved(approved: Bool)
}

public struct MascotStateSnapshot: Equatable, Sendable {
    public let state: MascotState
    public let lastMessage: String?
    public let awaitingApproval: ApprovalRequest?

    public init(
        state: MascotState,
        lastMessage: String? = nil,
        awaitingApproval: ApprovalRequest? = nil
    ) {
        self.state = state
        self.lastMessage = lastMessage
        self.awaitingApproval = awaitingApproval
    }
}

public struct MascotStateMachine: Sendable {
    private var snapshot: MascotStateSnapshot

    public init(initialState: MascotState = .hidden) {
        self.snapshot = MascotStateSnapshot(state: initialState)
    }

    public var current: MascotStateSnapshot {
        snapshot
    }

    @discardableResult
    public mutating func apply(_ event: MascotRuntimeEvent) -> MascotStateSnapshot {
        switch event {
        case let .commandStarted(command):
            snapshot = snapshot.replacing(state: state(for: command), message: nil, approval: snapshot.awaitingApproval)
        case let .commandFinished(command, status):
            snapshot = snapshot.replacing(state: stateAfter(command: command, status: status), message: nil, approval: nil)
        case let .voice(event):
            snapshot = snapshot.replacing(
                state: VoiceEventRouter.mascotState(for: event) ?? snapshot.state,
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

    private func state(for command: MascotCommand) -> MascotState {
        switch command {
        case .show:
            return .showing
        case .hide:
            return .hidden
        case .play, .morph, .gestureAt, .moveTo:
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

    private func stateAfter(command: MascotCommand, status: MascotRequestStatus) -> MascotState {
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

    private func state(forToolName name: String) -> MascotState {
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

private extension MascotStateSnapshot {
    func replacing(
        state: MascotState,
        message: String?,
        approval: ApprovalRequest?
    ) -> MascotStateSnapshot {
        MascotStateSnapshot(state: state, lastMessage: message, awaitingApproval: approval)
    }
}
