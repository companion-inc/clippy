import Foundation

public enum SidekickState: String, CaseIterable, Codable, Equatable, Sendable {
    case hidden
    case showing
    case idle
    case listening
    case hearing
    case speaking
    case thinking
    case screenVision
    case cameraVision
    case reading
    case searching
    case writing
    case computerControl
    case waitingApproval
    case done
    case blocked
    case error
}

public enum SidekickCommand: Equatable, Sendable {
    case show(animated: Bool)
    case hide(animated: Bool)
    case play(animation: String)
    case speak(text: String, tts: Bool)
    case think(text: String?)
    case gestureAt(x: Double, y: Double)
    case moveTo(x: Double, y: Double, duration: Double)
    case setState(SidekickState)
    case stopCurrent
    case stopAll
}

public enum SidekickRequestStatus: String, Equatable, Sendable {
    case queued
    case running
    case complete
    case failed
    case interrupted
}

public struct SidekickAction: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let command: SidekickCommand

    public init(id: UUID = UUID(), command: SidekickCommand) {
        self.id = id
        self.command = command
    }
}

public struct SidekickRequestSnapshot: Equatable, Sendable {
    public let id: UUID
    public let command: SidekickCommand
    public let status: SidekickRequestStatus
}
