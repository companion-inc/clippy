import Foundation

public enum ClippyState: String, CaseIterable, Codable, Equatable, Sendable {
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

public enum ClippyCommand: Equatable, Sendable {
    case show(animated: Bool)
    case hide(animated: Bool)
    case play(animation: String)
    case speak(text: String, tts: Bool)
    case think(text: String?)
    case gestureAt(x: Double, y: Double)
    case moveTo(x: Double, y: Double, duration: Double)
    case setState(ClippyState)
    case stopCurrent
    case stopAll
}

public enum ClippyRequestStatus: String, Equatable, Sendable {
    case queued
    case running
    case complete
    case failed
    case interrupted
}

public struct ClippyAction: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let command: ClippyCommand

    public init(id: UUID = UUID(), command: ClippyCommand) {
        self.id = id
        self.command = command
    }
}

public struct ClippyRequestSnapshot: Equatable, Sendable {
    public let id: UUID
    public let command: ClippyCommand
    public let status: ClippyRequestStatus
}
