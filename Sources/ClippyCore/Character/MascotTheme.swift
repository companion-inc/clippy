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
        regularFontName: String = "MS Sans Serif",
        boldFontName: String = "MS Sans Serif Bold"
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
            .thinking: MascotAnimationBinding(animationName: "IdleHeadScratch", repeatsUntilStateChange: true),
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
}
