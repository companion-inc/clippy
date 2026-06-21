import Foundation

public enum AssistantInputMode: String, Codable, Equatable, Sendable {
    case text
    case voice
}

public enum AssistantResponseMode: String, Codable, Equatable, Sendable {
    case bubble
    case voice
    case automatic
}

public struct DesktopTaskContext: Codable, Equatable, Sendable {
    public let focusedAppBundleID: String?
    public let focusedWindowTitle: String?
    public let screenObservationID: UUID?
    public let cameraObservationID: UUID?

    public init(
        focusedAppBundleID: String? = nil,
        focusedWindowTitle: String? = nil,
        screenObservationID: UUID? = nil,
        cameraObservationID: UUID? = nil
    ) {
        self.focusedAppBundleID = focusedAppBundleID
        self.focusedWindowTitle = focusedWindowTitle
        self.screenObservationID = screenObservationID
        self.cameraObservationID = cameraObservationID
    }
}

public struct DesktopTaskRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let inputMode: AssistantInputMode
    public let rawText: String
    public let interpretedTask: String
    public let context: DesktopTaskContext
    public let preferredResponseMode: AssistantResponseMode
    public let requiresApprovalBeforeExternalAction: Bool

    public init(
        id: UUID = UUID(),
        inputMode: AssistantInputMode,
        rawText: String,
        interpretedTask: String? = nil,
        context: DesktopTaskContext = DesktopTaskContext(),
        preferredResponseMode: AssistantResponseMode = .automatic,
        requiresApprovalBeforeExternalAction: Bool = true
    ) {
        self.id = id
        self.inputMode = inputMode
        self.rawText = rawText
        self.interpretedTask = interpretedTask ?? rawText
        self.context = context
        self.preferredResponseMode = preferredResponseMode
        self.requiresApprovalBeforeExternalAction = requiresApprovalBeforeExternalAction
    }
}

