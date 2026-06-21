import Foundation

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

    public var sidekickState: SidekickState {
        switch self {
        case .idle, .sleeping:
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
        }
    }
}
