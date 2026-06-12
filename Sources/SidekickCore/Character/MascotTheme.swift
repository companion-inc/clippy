import AppKit

public struct MascotAnimationBinding {
    public let animationName: String
    public let repeatsUntilStateChange: Bool

    public init(animationName: String, repeatsUntilStateChange: Bool = false) {
        self.animationName = animationName
        self.repeatsUntilStateChange = repeatsUntilStateChange
    }
}

public struct MascotBalloonTheme {
    public let fillColor: NSColor
    public let strokeColor: NSColor
    public let textColor: NSColor
    public let mutedTextColor: NSColor
    public let borderWidth: CGFloat
    public let cornerRadius: CGFloat
    public let tailHeight: CGFloat
    public let tailHalfWidth: CGFloat
    public let tailTipOffset: CGFloat
    public let minWidth: CGFloat
    public let maxWidth: CGFloat
    public let approvalWidth: CGFloat
    public let pad: CGFloat
    public let minInputHeight: CGFloat
    public let maxInputHeight: CGFloat
    public let regularFontName: String
    public let boldFontName: String

    public init(
        fillColor: NSColor,
        strokeColor: NSColor,
        textColor: NSColor = .black,
        mutedTextColor: NSColor = NSColor.black.withAlphaComponent(0.45),
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 5,
        tailHeight: CGFloat = 12,
        tailHalfWidth: CGFloat = 8,
        tailTipOffset: CGFloat = -4,
        minWidth: CGFloat = 150,
        maxWidth: CGFloat = 300,
        approvalWidth: CGFloat = 270,
        pad: CGFloat = 11,
        minInputHeight: CGFloat = 22,
        maxInputHeight: CGFloat = 112,
        regularFontName: String = "Microsoft Sans Serif",
        boldFontName: String = "Microsoft Sans Serif Bold"
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.textColor = textColor
        self.mutedTextColor = mutedTextColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.tailHeight = tailHeight
        self.tailHalfWidth = tailHalfWidth
        self.tailTipOffset = tailTipOffset
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.approvalWidth = approvalWidth
        self.pad = pad
        self.minInputHeight = minInputHeight
        self.maxInputHeight = maxInputHeight
        self.regularFontName = regularFontName
        self.boldFontName = boldFontName
    }

    public static let clippy = MascotBalloonTheme(
        fillColor: NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.8, alpha: 1),
        strokeColor: .black
    )

    public static let morph = MascotBalloonTheme(
        fillColor: NSColor(calibratedRed: 0.94, green: 0.98, blue: 1.0, alpha: 1),
        strokeColor: NSColor(calibratedWhite: 0.18, alpha: 1),
        mutedTextColor: NSColor.black.withAlphaComponent(0.5),
        cornerRadius: 6
    )

    public static let claudeCode = MascotBalloonTheme(
        fillColor: NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.78, alpha: 1),
        strokeColor: NSColor(calibratedRed: 0.22, green: 0.10, blue: 0.06, alpha: 1),
        mutedTextColor: NSColor(calibratedRed: 0.22, green: 0.10, blue: 0.06, alpha: 0.55),
        cornerRadius: 3,
        tailHeight: 11,
        regularFontName: "Menlo",
        boldFontName: "Menlo-Bold"
    )

    public static let codex = MascotBalloonTheme(
        fillColor: NSColor(calibratedRed: 0.86, green: 1.00, blue: 0.88, alpha: 1),
        strokeColor: NSColor(calibratedRed: 0.02, green: 0.12, blue: 0.08, alpha: 1),
        mutedTextColor: NSColor(calibratedRed: 0.02, green: 0.12, blue: 0.08, alpha: 0.55),
        cornerRadius: 2,
        tailHeight: 11,
        regularFontName: "Menlo",
        boldFontName: "Menlo-Bold"
    )
}

public struct MascotTheme {
    public let id: String
    public let displayName: String
    public let balloon: MascotBalloonTheme
    public let askPlaceholder: String
    public let chatMenuTitle: String
    public let greetingText: String
    public let greetingAnimationName: String
    public let openInputAnimationName: String
    public let replyAnimationName: String
    public let errorAnimationName: String
    public let fallbackGestureAnimationName: String
    private let activityAnimations: [AgentActivityState: MascotAnimationBinding]

    public init(
        id: String,
        displayName: String,
        balloon: MascotBalloonTheme,
        askPlaceholder: String,
        chatMenuTitle: String,
        greetingText: String,
        greetingAnimationName: String,
        openInputAnimationName: String,
        replyAnimationName: String,
        errorAnimationName: String,
        fallbackGestureAnimationName: String,
        activityAnimations: [AgentActivityState: MascotAnimationBinding]
    ) {
        self.id = id
        self.displayName = displayName
        self.balloon = balloon
        self.askPlaceholder = askPlaceholder
        self.chatMenuTitle = chatMenuTitle
        self.greetingText = greetingText
        self.greetingAnimationName = greetingAnimationName
        self.openInputAnimationName = openInputAnimationName
        self.replyAnimationName = replyAnimationName
        self.errorAnimationName = errorAnimationName
        self.fallbackGestureAnimationName = fallbackGestureAnimationName
        self.activityAnimations = activityAnimations
    }

    public func animation(for state: AgentActivityState) -> MascotAnimationBinding? {
        activityAnimations[state]
    }

    public static let clippy = MascotTheme(
        id: "clippy",
        displayName: "Clippy",
        balloon: .clippy,
        askPlaceholder: "Ask Clippy…",
        chatMenuTitle: "Chat with Clippy…",
        greetingText: "It looks like you're using a Mac. Double-click me to chat!",
        greetingAnimationName: "Greeting",
        openInputAnimationName: "GetAttention",
        replyAnimationName: "Explain",
        errorAnimationName: "Alert",
        fallbackGestureAnimationName: "Wave",
        activityAnimations: [
            .thinking: MascotAnimationBinding(animationName: "Thinking", repeatsUntilStateChange: true),
            .working: MascotAnimationBinding(animationName: "Processing", repeatsUntilStateChange: true),
            .juggling: MascotAnimationBinding(animationName: "GetArtsy", repeatsUntilStateChange: true),
            .notification: MascotAnimationBinding(animationName: "Alert"),
            .attention: MascotAnimationBinding(animationName: "Congratulate"),
            .error: MascotAnimationBinding(animationName: "Alert"),
            .sweeping: MascotAnimationBinding(animationName: "EmptyTrash"),
            .carrying: MascotAnimationBinding(animationName: "Save"),
            .sleeping: MascotAnimationBinding(animationName: "IdleSnooze"),
        ]
    )

    public static let morph = MascotTheme(
        id: "morph",
        displayName: "Morph Mascot",
        balloon: .morph,
        askPlaceholder: "Ask Morph…",
        chatMenuTitle: "Chat with Morph…",
        greetingText: "Double-click me to chat.",
        greetingAnimationName: "Greeting",
        openInputAnimationName: "Wave",
        replyAnimationName: "Explain",
        errorAnimationName: "Alert",
        fallbackGestureAnimationName: "Wave",
        activityAnimations: [
            .thinking: MascotAnimationBinding(animationName: "Glance"),
            .working: MascotAnimationBinding(animationName: "Sway"),
            .juggling: MascotAnimationBinding(animationName: "RaiseBrows"),
            .notification: MascotAnimationBinding(animationName: "Alert"),
            .attention: MascotAnimationBinding(animationName: "Wave"),
            .error: MascotAnimationBinding(animationName: "Alert"),
            .sweeping: MascotAnimationBinding(animationName: "Glance"),
            .carrying: MascotAnimationBinding(animationName: "Explain"),
            .sleeping: MascotAnimationBinding(animationName: "Blink"),
        ]
    )

    public static let claudeCode = MascotTheme(
        id: "claude-code",
        displayName: "Claude Code",
        balloon: .claudeCode,
        askPlaceholder: "Ask Claude Code…",
        chatMenuTitle: "Chat with Claude Code…",
        greetingText: "Claude Code sidekick online. Double-click to chat.",
        greetingAnimationName: "ClaudeGreeting",
        openInputAnimationName: "ClaudeWave",
        replyAnimationName: "ClaudeExplain",
        errorAnimationName: "ClaudeError",
        fallbackGestureAnimationName: "ClaudeWave",
        activityAnimations: [
            .thinking: MascotAnimationBinding(animationName: "ClaudeThinking", repeatsUntilStateChange: true),
            .working: MascotAnimationBinding(animationName: "ClaudeWorking", repeatsUntilStateChange: true),
            .juggling: MascotAnimationBinding(animationName: "ClaudeJuggling", repeatsUntilStateChange: true),
            .notification: MascotAnimationBinding(animationName: "ClaudeNotification"),
            .attention: MascotAnimationBinding(animationName: "ClaudeHappy"),
            .error: MascotAnimationBinding(animationName: "ClaudeError"),
            .sweeping: MascotAnimationBinding(animationName: "ClaudeSweeping"),
            .carrying: MascotAnimationBinding(animationName: "ClaudeCarrying"),
            .sleeping: MascotAnimationBinding(animationName: "ClaudeSleeping"),
        ]
    )

    public static let codex = MascotTheme(
        id: "codex",
        displayName: "Codex",
        balloon: .codex,
        askPlaceholder: "Ask Codex…",
        chatMenuTitle: "Chat with Codex…",
        greetingText: "Codex sidekick online. Double-click to chat.",
        greetingAnimationName: "CodexGreeting",
        openInputAnimationName: "CodexWave",
        replyAnimationName: "CodexExplain",
        errorAnimationName: "CodexError",
        fallbackGestureAnimationName: "CodexWave",
        activityAnimations: [
            .thinking: MascotAnimationBinding(animationName: "CodexThinking", repeatsUntilStateChange: true),
            .working: MascotAnimationBinding(animationName: "CodexWorking", repeatsUntilStateChange: true),
            .juggling: MascotAnimationBinding(animationName: "CodexJuggling", repeatsUntilStateChange: true),
            .notification: MascotAnimationBinding(animationName: "CodexNotification"),
            .attention: MascotAnimationBinding(animationName: "CodexHappy"),
            .error: MascotAnimationBinding(animationName: "CodexError"),
            .sweeping: MascotAnimationBinding(animationName: "CodexSweeping"),
            .carrying: MascotAnimationBinding(animationName: "CodexCarrying"),
            .sleeping: MascotAnimationBinding(animationName: "CodexSleeping"),
        ]
    )
}
