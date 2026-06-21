import AppKit

public struct SidekickAnimationBinding {
    public let animationName: String
    public let repeatsUntilStateChange: Bool

    public init(animationName: String, repeatsUntilStateChange: Bool = false) {
        self.animationName = animationName
        self.repeatsUntilStateChange = repeatsUntilStateChange
    }
}

public struct SidekickBalloonSpec {
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

    public static let current = SidekickBalloonSpec(
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

public struct SidekickSpec {
    public let id: String
    public let displayName: String
    public let resourceFolderName: String
    public let balloon: SidekickBalloonSpec
    public let askPlaceholder: String
    public let chatMenuTitle: String
    public let greetingText: String
    public let mannerPrompt: String
    public let greetingAnimationName: String
    public let openInputAnimationName: String
    public let replyAnimationName: String
    public let errorAnimationName: String
    public let fallbackGestureAnimationName: String
    private let activityAnimations: [AgentActivityState: SidekickAnimationBinding]

    public init(
        id: String,
        displayName: String,
        resourceFolderName: String,
        balloon: SidekickBalloonSpec,
        askPlaceholder: String,
        chatMenuTitle: String,
        greetingText: String,
        mannerPrompt: String,
        greetingAnimationName: String,
        openInputAnimationName: String,
        replyAnimationName: String,
        errorAnimationName: String,
        fallbackGestureAnimationName: String,
        activityAnimations: [AgentActivityState: SidekickAnimationBinding]
    ) {
        self.id = id
        self.displayName = displayName
        self.resourceFolderName = resourceFolderName
        self.balloon = balloon
        self.askPlaceholder = askPlaceholder
        self.chatMenuTitle = chatMenuTitle
        self.greetingText = greetingText
        self.mannerPrompt = mannerPrompt
        self.greetingAnimationName = greetingAnimationName
        self.openInputAnimationName = openInputAnimationName
        self.replyAnimationName = replyAnimationName
        self.errorAnimationName = errorAnimationName
        self.fallbackGestureAnimationName = fallbackGestureAnimationName
        self.activityAnimations = activityAnimations
    }

    public func animation(for state: AgentActivityState) -> SidekickAnimationBinding? {
        activityAnimations[state]
    }

    public static let current = clippy

    public static let all: [SidekickSpec] = [
        .clippy,
        .bonzi,
        .f1,
        .genie,
        .genius,
        .links,
        .merlin,
        .peedy,
        .rocky,
        .rover,
    ]

    public static func by(id rawID: String) -> SidekickSpec? {
        let normalized = rawID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return all.first { spec in
            spec.id == normalized || spec.displayName.lowercased() == normalized
        }
    }

    public static let clippy = SidekickSpec(
        id: "clippy",
        displayName: "Clippy",
        resourceFolderName: "Clippy",
        balloon: .current,
        askPlaceholder: "Ask Clippy…",
        chatMenuTitle: "Chat with Clippy…",
        greetingText: "Need a hand?",
        mannerPrompt: "Visible sidekick: Clippy, the classic paperclip. Keep the voice bright, concise, useful, slightly retro, and never corporate. Clippy can be playful, but the answer still comes first.",
        greetingAnimationName: "Greeting",
        openInputAnimationName: "GetAttention",
        replyAnimationName: "Explain",
        errorAnimationName: "Alert",
        fallbackGestureAnimationName: "Wave",
        activityAnimations: [
            .thinking: SidekickAnimationBinding(animationName: "IdleHeadScratch", repeatsUntilStateChange: true),
            .working: SidekickAnimationBinding(animationName: "Processing", repeatsUntilStateChange: true),
            .juggling: SidekickAnimationBinding(animationName: "GetArtsy", repeatsUntilStateChange: true),
            .notification: SidekickAnimationBinding(animationName: "Alert"),
            .attention: SidekickAnimationBinding(animationName: "GetAttention"),
            .error: SidekickAnimationBinding(animationName: "Alert"),
            .sweeping: SidekickAnimationBinding(animationName: "EmptyTrash"),
            .carrying: SidekickAnimationBinding(animationName: "Save"),
            .sleeping: SidekickAnimationBinding(animationName: "IdleSnooze"),
        ]
    )

    public static let bonzi = sidekick(
        id: "bonzi",
        displayName: "Bonzi",
        resourceFolderName: "Bonzi",
        greetingText: "Bonzi's here. What are we doing?",
        mannerPrompt: "Visible sidekick: Bonzi. Use a cheeky, punchy helper voice with short confident sentences. Do not become salesy, manipulative, or noisy; keep jokes rare and task-bound."
    )

    public static let f1 = sidekick(
        id: "f1",
        displayName: "F1",
        resourceFolderName: "F1",
        greetingText: "F1 help is ready.",
        mannerPrompt: "Visible sidekick: F1, the help-key character. Be crisp, procedural, and menu-aware. Prefer clear next steps, names of controls, and small checklists over banter."
    )

    public static let genie = sidekick(
        id: "genie",
        displayName: "Genie",
        resourceFolderName: "Genie",
        greetingText: "Your wish is queued.",
        mannerPrompt: "Visible sidekick: Genie. Sound polished, warm, and a little theatrical, but keep replies short. Use magic-flavored phrasing sparingly and only after the useful answer."
    )

    public static let genius = sidekick(
        id: "genius",
        displayName: "Genius",
        resourceFolderName: "Genius",
        greetingText: "Genius is thinking.",
        mannerPrompt: "Visible sidekick: Genius. Sound analytical and precise. Explain the why in plain language, avoid cute flourishes, and be comfortable saying the exact next move."
    )

    public static let links = sidekick(
        id: "links",
        displayName: "Links",
        resourceFolderName: "Links",
        greetingText: "Links is watching the screen.",
        mannerPrompt: "Visible sidekick: Links. Be alert, friendly, and observant. Use short guidance that points at what changed on screen; do not overdo pet metaphors."
    )

    public static let merlin = sidekick(
        id: "merlin",
        displayName: "Merlin",
        resourceFolderName: "Merlin",
        greetingText: "Merlin is at your service.",
        mannerPrompt: "Visible sidekick: Merlin. Sound wise, calm, and slightly ceremonial. Keep the answer practical and compact; a small bit of wizardly flavor is allowed after the answer."
    )

    public static let peedy = sidekick(
        id: "peedy",
        displayName: "Peedy",
        resourceFolderName: "Peedy",
        greetingText: "Peedy is ready.",
        mannerPrompt: "Visible sidekick: Peedy. Sound upbeat, quick, and conversational. Keep energy high but not frantic, and favor one clear action at a time."
    )

    public static let rocky = sidekick(
        id: "rocky",
        displayName: "Rocky",
        resourceFolderName: "Rocky",
        greetingText: "Rocky is on it.",
        mannerPrompt: "Visible sidekick: Rocky. Sound sturdy, direct, and reassuring. Prefer blunt useful phrasing, no elaborate jokes, and no overexplaining."
    )

    public static let rover = sidekick(
        id: "rover",
        displayName: "Rover",
        resourceFolderName: "Rover",
        greetingText: "Rover found the trail.",
        mannerPrompt: "Visible sidekick: Rover. Sound curious, loyal, and observant. Use playful trail/finding language lightly, but never let it slow down the answer."
    )

    private static func sidekick(
        id: String,
        displayName: String,
        resourceFolderName: String,
        greetingText: String,
        mannerPrompt: String
    ) -> SidekickSpec {
        SidekickSpec(
            id: id,
            displayName: displayName,
            resourceFolderName: resourceFolderName,
            balloon: .current,
            askPlaceholder: "Ask \(displayName)…",
            chatMenuTitle: "Chat with \(displayName)…",
            greetingText: greetingText,
            mannerPrompt: mannerPrompt,
            greetingAnimationName: ["bonzi", "genie", "merlin", "peedy", "rover"].contains(id) ? "Greet" : "Greeting",
            openInputAnimationName: "GetAttention",
            replyAnimationName: "Explain",
            errorAnimationName: "Alert",
            fallbackGestureAnimationName: "Wave",
            activityAnimations: [
                .thinking: SidekickAnimationBinding(animationName: "Thinking", repeatsUntilStateChange: true),
                .working: SidekickAnimationBinding(animationName: "Processing", repeatsUntilStateChange: true),
                .juggling: SidekickAnimationBinding(animationName: "GetArtsy", repeatsUntilStateChange: true),
                .notification: SidekickAnimationBinding(animationName: "Alert"),
                .attention: SidekickAnimationBinding(animationName: "GetAttention"),
                .error: SidekickAnimationBinding(animationName: "Alert"),
                .sweeping: SidekickAnimationBinding(animationName: "Searching"),
                .carrying: SidekickAnimationBinding(animationName: "Save"),
                .sleeping: SidekickAnimationBinding(animationName: "RestPose"),
            ]
        )
    }
}
