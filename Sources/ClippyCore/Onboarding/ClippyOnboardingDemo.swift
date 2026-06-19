import Foundation

public enum ClippyOnboardingResumePoint: String, CaseIterable, Sendable {
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

    public static let defaultsKey = "ClippyOnboardingResumePoint"

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

public enum ClippyOnboardingDemo {
    public static let guidedIntroText = "Let me show you on the screen you're already using. I'll pick one visible thing and point it out."
    public static let guidedWorkingText = "Looking at your screen"
    public static let visibleTaskLine = ""
    public static let controlsText = """
    Last thing: click me to open or close chat. Press Control+Space to type from anywhere. Hold Control+Option to talk. Hold Control to mark the screen, or tap Control twice for annotation mode. Right-click me for settings.
    """

    public static func taskPrompt() -> String {
        return """
        [Clippy onboarding demo task]
        Use only the current screenshot and desktop context. Do not open an app, browser, file, tab, URL, or demo page.

        Pick one concrete visible thing already on the user's current screen and point it out with Clippy:
        - Prefer a clear app control, title, heading, icon, image, chart, button, or visible work area near the middle of the screenshot.
        - Avoid private personal content. Do not quote messages, emails, contacts, addresses, filenames, keys, tokens, or long text from the screen.
        - If the visible screen is too sensitive or blank, point to a harmless app area or say you are ready without a visual tag.

        Reply with one short Clippy sentence and exactly one renderable visual tag when a safe visible target exists.
        Use [POINT:x,y:label] for one precise spot or [HIGHLIGHT:x,y,r:label] for one area.
        Coordinates are integer pixels in the screenshot, top-left origin. Do not mention internal tools.
        """
    }
}
