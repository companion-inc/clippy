import Foundation

public struct SidekickBackgroundScreenSuggestionState: Equatable, Sendable {
    public let enabled: Bool
    public let isTurnRunning: Bool
    public let isVoiceCaptureActive: Bool
    public let isPushToTalkHeld: Bool
    public let isTTSSpeaking: Bool
    public let isPresentingChoices: Bool
    public let isInputMode: Bool
    public let isUserAnnotating: Bool
    public let isAnnotationHoldActive: Bool
    public let isOnboardingActive: Bool
    public let isWorkflowRecording: Bool
    public let hasGuidedTarget: Bool
    public let isSidekickHidden: Bool

    public init(
        enabled: Bool,
        isTurnRunning: Bool,
        isVoiceCaptureActive: Bool,
        isPushToTalkHeld: Bool,
        isTTSSpeaking: Bool,
        isPresentingChoices: Bool,
        isInputMode: Bool,
        isUserAnnotating: Bool,
        isAnnotationHoldActive: Bool,
        isOnboardingActive: Bool,
        isWorkflowRecording: Bool,
        hasGuidedTarget: Bool,
        isSidekickHidden: Bool
    ) {
        self.enabled = enabled
        self.isTurnRunning = isTurnRunning
        self.isVoiceCaptureActive = isVoiceCaptureActive
        self.isPushToTalkHeld = isPushToTalkHeld
        self.isTTSSpeaking = isTTSSpeaking
        self.isPresentingChoices = isPresentingChoices
        self.isInputMode = isInputMode
        self.isUserAnnotating = isUserAnnotating
        self.isAnnotationHoldActive = isAnnotationHoldActive
        self.isOnboardingActive = isOnboardingActive
        self.isWorkflowRecording = isWorkflowRecording
        self.hasGuidedTarget = hasGuidedTarget
        self.isSidekickHidden = isSidekickHidden
    }
}

public struct SidekickBackgroundScreenWakeDecision: Equatable, Sendable {
    public let shouldShowOptions: Bool
    public let reason: String?

    public init(shouldShowOptions: Bool, reason: String?) {
        self.shouldShowOptions = shouldShowOptions
        self.reason = reason
    }
}

public enum SidekickBackgroundScreenSuggestions {
    public static let defaultIntervalSeconds: TimeInterval = 5
    public static let maxConsecutiveWakeFailures = 3

    public static func shouldRun(state: SidekickBackgroundScreenSuggestionState) -> Bool {
        state.enabled
            && state.isTurnRunning == false
            && state.isVoiceCaptureActive == false
            && state.isPushToTalkHeld == false
            && state.isTTSSpeaking == false
            && state.isPresentingChoices == false
            && state.isInputMode == false
            && state.isUserAnnotating == false
            && state.isAnnotationHoldActive == false
            && state.isOnboardingActive == false
            && state.isWorkflowRecording == false
            && state.hasGuidedTarget == false
            && state.isSidekickHidden == false
    }

    public static func shouldDisable(afterConsecutiveWakeFailures count: Int) -> Bool {
        count >= maxConsecutiveWakeFailures
    }

    public static let wakeSchema = AgentOutputSchema(jsonObject: [
        "type": "object",
        "additionalProperties": false,
        "required": ["shouldShowOptions", "reason"],
        "properties": [
            "shouldShowOptions": [
                "type": "boolean",
                "description": "True only when this idle background screen check should interrupt the user with Sidekick options.",
            ],
            "reason": [
                "type": "string",
                "description": "Short internal reason for the decision.",
                "maxLength": 140,
            ],
        ],
    ])

    public static func wakePrompt() -> String {
        """
        [Sidekick idle background screen wake check]
        Sidekick is quietly checking the screen while the user is idle. This check may run every few seconds, so be very selective.

        Decide whether Sidekick should interrupt by showing option buttons now.

        Return shouldShowOptions=true only when the current screen clearly has a high-value, timely, actionable thing Sidekick can help with, such as:
        - an error, failed action, blocked setup, or confusing modal
        - a message/composer/form where drafting, explaining, or choosing the next step is plainly useful
        - a visible decision point with meaningful choices
        - an urgent notification or reminder visible on screen

        Return false for passive reading, normal browsing, dashboards, videos, finished work, idle desktops, already-visible Sidekick choices, or anything that is merely visible but not asking for help.
        This wake check does not perform the task and does not write option labels. It only decides whether the medium option generator should run.
        """
    }

    public static func parseWakeDecision(from text: String) -> SidekickBackgroundScreenWakeDecision? {
        guard let data = jsonObjectData(in: text),
              let decoded = try? JSONDecoder().decode(WakeDecisionEnvelope.self, from: data)
        else {
            return nil
        }
        return SidekickBackgroundScreenWakeDecision(
            shouldShowOptions: decoded.shouldShowOptions,
            reason: clean(decoded.reason)
        )
    }

    private struct WakeDecisionEnvelope: Decodable {
        let shouldShowOptions: Bool
        let reason: String
    }

    private static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard cleaned.isEmpty == false else { return nil }
        return String(cleaned.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func jsonObjectData(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var isEscaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index]).data(using: .utf8)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
