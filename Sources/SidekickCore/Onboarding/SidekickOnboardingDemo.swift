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
        if rawValue == "permission"
            || rawValue == "permissionWalkthrough"
            || rawValue == "screenHelp"
            || rawValue == "fileAccess"
            || rawValue == "demo"
            || rawValue == "demoComposer"
        {
            return .controls
        }
        guard let rawValue, let point = Self(rawValue: rawValue) else {
            return .welcome
        }
        return point
    }
}

public enum SidekickOnboardingDemo {
    public static let guidedIntroText = ""
    public static let guidedWorkingText = ""
    public static let visibleTaskLine = ""
    public static let controlsText = """
    That's it! Click me to chat, double-click me for quick options, press Control+Space to type from anywhere, or hold Control+Option to talk. Right-click me for everything else.
    """

    /// First-run onboarding no longer performs a screen-reading demo. Screen,
    /// Accessibility, and file permissions are requested later at the feature boundary.
    public static let demoRequestText = ""
}
