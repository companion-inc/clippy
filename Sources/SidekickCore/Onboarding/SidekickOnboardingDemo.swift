import Foundation

public enum SidekickOnboardingResumePoint: String, CaseIterable, Sendable {
    case welcome
    case brainChoice
    case brainHelp
    case chatGPT
    case claude
    case listening
    case voice
    case screenHelp
    case fileAccess
    case demo
    case controls

    public static let defaultsKey = "SidekickOnboardingResumePoint"

    public static func savedPoint(from rawValue: String?) -> Self {
        if rawValue == "demoComposer" {
            return .demo
        }
        if rawValue == "permission" || rawValue == "permissionWalkthrough" {
            return .screenHelp
        }
        guard let rawValue, let point = Self(rawValue: rawValue) else {
            return .welcome
        }
        return point
    }
}

public enum SidekickOnboardingDemo {
    public static let guidedIntroText = "Okay, watch this — I'll find something on your screen and point right at it."
    public static let guidedWorkingText = "Looking at your screen"
    public static let visibleTaskLine = ""
    public static let controlsText = """
    That's it! Click me to chat, double-click me for quick options, press Control+Space to type from anywhere, or hold Control+Option to talk. Right-click me for everything else.
    """

    /// The demo is just a normal Sidekick turn. We send the same plain request a
    /// user could type and let the regular pipeline do the rest: it always
    /// attaches a fresh screenshot, recognizes the pointing intent, and appends
    /// the standard visual-grounding contract. No bespoke demo prompt and no
    /// extra "avoid private content" hedging — Sidekick is already running locally
    /// on the user's own screen at their request, so the demo behaves exactly
    /// like real use.
    public static let demoRequestText = "Point out something interesting on my screen."
}
