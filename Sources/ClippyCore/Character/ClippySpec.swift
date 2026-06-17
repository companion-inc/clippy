import AppKit

public struct ClippyAnimationBinding {
    public let animationName: String
    public let repeatsUntilStateChange: Bool

    public init(animationName: String, repeatsUntilStateChange: Bool = false) {
        self.animationName = animationName
        self.repeatsUntilStateChange = repeatsUntilStateChange
    }
}

public struct ClippyBalloonSpec {
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
    public let shadowOffset: CGSize
    public let shadowColor: NSColor
    public let messageFontSize: CGFloat
    public let inputFontSize: CGFloat
    public let regularFontName: String
    public let boldFontName: String

    public init(
        fillColor: NSColor,
        strokeColor: NSColor,
        textColor: NSColor = .black,
        mutedTextColor: NSColor = NSColor.black.withAlphaComponent(0.45),
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 11,
        tailHeight: CGFloat = 13,
        tailHalfWidth: CGFloat = 12,
        tailTipOffset: CGFloat = -7,
        minWidth: CGFloat = 150,
        maxWidth: CGFloat = 300,
        approvalWidth: CGFloat = 270,
        pad: CGFloat = 11,
        minInputHeight: CGFloat = 22,
        maxInputHeight: CGFloat = 112,
        shadowOffset: CGSize = CGSize(width: 3, height: -3),
        shadowColor: NSColor = NSColor(calibratedRed: 0.8, green: 0.8, blue: 0.6, alpha: 1),
        messageFontSize: CGFloat = 13,
        inputFontSize: CGFloat = 13,
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
        self.shadowOffset = shadowOffset
        self.shadowColor = shadowColor
        self.messageFontSize = messageFontSize
        self.inputFontSize = inputFontSize
        self.regularFontName = regularFontName
        self.boldFontName = boldFontName
    }

    public static let current = ClippyBalloonSpec(
        fillColor: NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.8, alpha: 1),
        strokeColor: .black,
        cornerRadius: 10,
        tailHeight: 17,
        tailHalfWidth: 9,
        tailTipOffset: -11,
        minWidth: 220,
        maxWidth: 285,
        approvalWidth: 285,
        pad: 10,
        shadowOffset: .zero
    )
}

public struct ClippySpec {
    public let id: String
    public let displayName: String
    public let balloon: ClippyBalloonSpec
    public let askPlaceholder: String
    public let chatMenuTitle: String
    public let greetingText: String
    public let greetingAnimationName: String
    public let openInputAnimationName: String
    public let replyAnimationName: String
    public let errorAnimationName: String
    public let fallbackGestureAnimationName: String
    private let activityAnimations: [AgentActivityState: ClippyAnimationBinding]

    public init(
        id: String,
        displayName: String,
        balloon: ClippyBalloonSpec,
        askPlaceholder: String,
        chatMenuTitle: String,
        greetingText: String,
        greetingAnimationName: String,
        openInputAnimationName: String,
        replyAnimationName: String,
        errorAnimationName: String,
        fallbackGestureAnimationName: String,
        activityAnimations: [AgentActivityState: ClippyAnimationBinding]
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

    public func animation(for state: AgentActivityState) -> ClippyAnimationBinding? {
        activityAnimations[state]
    }

    public static let current = ClippySpec(
        id: "clippy",
        displayName: "Clippy",
        balloon: .current,
        askPlaceholder: "Ask Clippy…",
        chatMenuTitle: "Chat with Clippy…",
        greetingText: "Need a hand?",
        greetingAnimationName: "Greeting",
        openInputAnimationName: "GetAttention",
        replyAnimationName: "Explain",
        errorAnimationName: "Alert",
        fallbackGestureAnimationName: "Wave",
        activityAnimations: [
            .thinking: ClippyAnimationBinding(animationName: "IdleHeadScratch", repeatsUntilStateChange: true),
            .working: ClippyAnimationBinding(animationName: "Processing", repeatsUntilStateChange: true),
            .juggling: ClippyAnimationBinding(animationName: "GetArtsy", repeatsUntilStateChange: true),
            .notification: ClippyAnimationBinding(animationName: "Alert"),
            .attention: ClippyAnimationBinding(animationName: "Congratulate"),
            .error: ClippyAnimationBinding(animationName: "Alert"),
            .sweeping: ClippyAnimationBinding(animationName: "EmptyTrash"),
            .carrying: ClippyAnimationBinding(animationName: "Save"),
            .sleeping: ClippyAnimationBinding(animationName: "IdleSnooze"),
        ]
    )
}
