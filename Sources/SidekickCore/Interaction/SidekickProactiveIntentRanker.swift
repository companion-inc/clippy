import Foundation

public enum SidekickProactiveIntentAction: String, Equatable, Sendable {
    case doNothing
    case watchForChange
    case evaluateWithWakeModel
    case showOptions
}

public struct SidekickProactiveIntentDecision: Equatable, Sendable {
    public let action: SidekickProactiveIntentAction
    public let intent: String
    public let score: Double
    public let reason: String
    public let overridesFeedbackCooldown: Bool
    public let expectedEngagement: Double
    public let interruptionCost: Double
    public let candidateCount: Int

    public init(
        action: SidekickProactiveIntentAction,
        intent: String,
        score: Double,
        reason: String,
        overridesFeedbackCooldown: Bool,
        expectedEngagement: Double = 0,
        interruptionCost: Double = 0,
        candidateCount: Int = 0
    ) {
        self.action = action
        self.intent = intent
        self.score = score
        self.reason = reason
        self.overridesFeedbackCooldown = overridesFeedbackCooldown
        self.expectedEngagement = expectedEngagement
        self.interruptionCost = interruptionCost
        self.candidateCount = candidateCount
    }

    public var promptBlock: String {
        """
        [Local proactive intent ranker:
        - action: \(action.rawValue)
        - intent: \(intent)
        - score: \(String(format: "%.2f", score))
        - expected user engagement: \(String(format: "%.2f", expectedEngagement))
        - interruption cost: \(String(format: "%.2f", interruptionCost))
        - candidates ranked: \(candidateCount)
        - reason: \(reason)
        - timing rule: watchForChange means the current state may become useful later, but interrupting now would be premature
        ]
        """
    }

    public var logSummary: String {
        "action=\(action.rawValue) intent=\(intent) value=\(String(format: "%.2f", score)) engagement=\(String(format: "%.2f", expectedEngagement)) cost=\(String(format: "%.2f", interruptionCost)) candidates=\(candidateCount) reason=\(reason)"
    }
}

public enum SidekickProactiveIntentRanker {
    public static func rank(
        desktopContext: DesktopContextSnapshot,
        accessibilityTree: DesktopAccessibilityTreeSnapshot,
        feedback: SidekickSuggestionFeedbackSummary? = nil,
        now: Date = Date()
    ) -> SidekickProactiveIntentDecision {
        let features = Features(
            desktopContext: desktopContext,
            accessibilityTree: accessibilityTree,
            feedback: feedback,
            now: now
        )
        let candidates = CandidateGenerator.candidates(for: features)
        let ranked = candidates
            .map { candidate in
                RankedCandidate(candidate: candidate, features: features)
            }
            .sorted { lhs, rhs in
                lhs.score == rhs.score
                    ? lhs.expectedEngagement > rhs.expectedEngagement
                    : lhs.score > rhs.score
            }
        let top = ranked.first ?? RankedCandidate(
            candidate: .doNothing,
            features: features
        )

        if feedback?.shouldSuppress(now: now) == true,
           top.candidate.urgency < 0.85,
           let suppressed = ranked.first(where: {
               $0.candidate.behavior == .consider && $0.candidate.urgency < 0.85
           }) {
            return SidekickProactiveIntentDecision(
                action: .watchForChange,
                intent: suppressed.candidate.intent,
                score: suppressed.score,
                reason: "Recent ignored popup for this app/surface; keep watching unless a clearly urgent state appears.",
                overridesFeedbackCooldown: false,
                expectedEngagement: suppressed.expectedEngagement,
                interruptionCost: suppressed.interruptionCost,
                candidateCount: ranked.count
            )
        }

        if top.candidate.behavior == .watch {
            return decision(action: .watchForChange, ranked: top, candidateCount: ranked.count)
        }

        if top.candidate.canShowDirectly && top.score >= 0.74 {
            return decision(action: .showOptions, ranked: top, candidateCount: ranked.count)
        }
        if top.score >= 0.42 {
            return decision(action: .evaluateWithWakeModel, ranked: top, candidateCount: ranked.count)
        }
        return decision(action: .doNothing, ranked: top, candidateCount: ranked.count)
    }

    private static func decision(
        action: SidekickProactiveIntentAction,
        ranked: RankedCandidate,
        candidateCount: Int
    ) -> SidekickProactiveIntentDecision {
        SidekickProactiveIntentDecision(
            action: action,
            intent: ranked.candidate.intent,
            score: ranked.score,
            reason: ranked.candidate.reason,
            overridesFeedbackCooldown: ranked.candidate.urgency >= 0.85,
            expectedEngagement: ranked.expectedEngagement,
            interruptionCost: ranked.interruptionCost,
            candidateCount: candidateCount
        )
    }
}

private enum CandidateBehavior: Equatable {
    case ignore
    case watch
    case consider
}

private struct Candidate: Equatable {
    static let doNothing = Candidate(
        intent: "do_nothing",
        reason: "No meaningful user-value signal yet.",
        relevance: 0.10,
        actionability: 0,
        urgency: 0,
        novelty: 0.10,
        interruptionCost: 0,
        behavior: .ignore,
        canShowDirectly: false
    )

    let intent: String
    let reason: String
    let relevance: Double
    let actionability: Double
    let urgency: Double
    let novelty: Double
    let interruptionCost: Double
    let behavior: CandidateBehavior
    let canShowDirectly: Bool
}

private struct RankedCandidate: Equatable {
    let candidate: Candidate
    let expectedEngagement: Double
    let interruptionCost: Double
    let score: Double

    init(candidate: Candidate, features: Features) {
        let feedbackPenalty = candidate.urgency >= 0.85 || candidate.behavior == .watch || candidate.behavior == .ignore
            ? 0
            : features.feedbackPenalty
        let engagementBoost = candidate.behavior == .watch || candidate.behavior == .ignore
            ? 0
            : features.engagementBoost
        let expectedEngagement = Self.clamp(
            0.44 * candidate.relevance
                + 0.30 * candidate.actionability
                + 0.16 * candidate.urgency
                + 0.10 * candidate.novelty
                + engagementBoost
        )
        let interruptionCost = Self.clamp(
            candidate.interruptionCost
                + features.contextInterruptionPenalty
                + feedbackPenalty
        )
        self.candidate = candidate
        self.expectedEngagement = expectedEngagement
        self.interruptionCost = interruptionCost
        self.score = Self.clamp(expectedEngagement - interruptionCost)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

private enum CandidateGenerator {
    static func candidates(for features: Features) -> [Candidate] {
        var candidates = [Candidate.doNothing]

        if features.isFocusedDraft {
            candidates.append(Candidate(
                intent: "watch_focused_draft",
                reason: "User is actively composing; wait for a pause, send intent, error, or explicit summon.",
                relevance: 0.72,
                actionability: 0.24,
                urgency: 0.10,
                novelty: 0.20,
                interruptionCost: 0.52,
                behavior: .watch,
                canShowDirectly: false
            ))
        } else if features.isFocusedInput {
            candidates.append(Candidate(
                intent: "watch_focused_input",
                reason: "User is in an active input field; watch for completion or an error before interrupting.",
                relevance: 0.60,
                actionability: 0.22,
                urgency: 0.10,
                novelty: 0.18,
                interruptionCost: 0.48,
                behavior: .watch,
                canShowDirectly: false
            ))
        }

        if features.isMediaOrImportantViewing {
            candidates.append(Candidate(
                intent: "watch_important_viewing",
                reason: "Current state looks like media, video, or other watching; stay quiet and monitor for future transitions.",
                relevance: 0.62,
                actionability: 0.12,
                urgency: 0.08,
                novelty: 0.18,
                interruptionCost: 0.56,
                behavior: .watch,
                canShowDirectly: false
            ))
        }

        if features.isPassiveReading {
            candidates.append(Candidate(
                intent: "watch_passive_reading",
                reason: "User appears to be reading or browsing without a current obstacle; monitor instead of interrupting.",
                relevance: 0.48,
                actionability: 0.10,
                urgency: 0.05,
                novelty: 0.14,
                interruptionCost: 0.44,
                behavior: .watch,
                canShowDirectly: false
            ))
        }

        if features.hasError {
            candidates.append(Candidate(
                intent: "explain_or_fix_error",
                reason: "Visible error or failed state is a high-value interruption point.",
                relevance: 0.92,
                actionability: 0.92,
                urgency: 0.95,
                novelty: 0.62,
                interruptionCost: 0.10,
                behavior: .consider,
                canShowDirectly: true
            ))
        }

        if features.hasUrgentNotification {
            candidates.append(Candidate(
                intent: "handle_urgent_notification",
                reason: "Visible notification or reminder has urgent timing language.",
                relevance: 0.88,
                actionability: 0.78,
                urgency: 0.90,
                novelty: 0.58,
                interruptionCost: 0.14,
                behavior: .consider,
                canShowDirectly: true
            ))
        } else if features.hasNotification {
            candidates.append(Candidate(
                intent: "handle_notification",
                reason: "Visible notification may be actionable, but needs confirmation before interrupting.",
                relevance: 0.58,
                actionability: 0.52,
                urgency: 0.42,
                novelty: 0.46,
                interruptionCost: 0.24,
                behavior: .consider,
                canShowDirectly: false
            ))
        }

        if features.hasMeaningfulDialog {
            candidates.append(Candidate(
                intent: "help_with_dialog",
                reason: "A meaningful dialog or sheet is visible; user may need a decision or explanation.",
                relevance: 0.70,
                actionability: 0.66,
                urgency: 0.58,
                novelty: 0.44,
                interruptionCost: 0.22,
                behavior: .consider,
                canShowDirectly: false
            ))
        }

        if features.hasDecisionPoint && features.isFocusedDraft == false && features.isSystemChromeNoise == false {
            candidates.append(Candidate(
                intent: "help_choose_next_step",
                reason: "Meaningful visible actions make this a possible decision point.",
                relevance: 0.64,
                actionability: 0.66,
                urgency: 0.44,
                novelty: 0.40,
                interruptionCost: 0.24,
                behavior: .consider,
                canShowDirectly: false
            ))
        }

        if features.hasForm && features.isFocusedInput == false && features.isFocusedDraft == false {
            candidates.append(Candidate(
                intent: "help_with_form",
                reason: "Form-like controls are visible without active typing.",
                relevance: 0.58,
                actionability: 0.58,
                urgency: 0.30,
                novelty: 0.36,
                interruptionCost: 0.28,
                behavior: .consider,
                canShowDirectly: false
            ))
        }

        return candidates
    }
}

private struct Features {
    let isFocusedDraft: Bool
    let isFocusedInput: Bool
    let hasForm: Bool
    let hasDialog: Bool
    let hasMeaningfulDialog: Bool
    let hasError: Bool
    let hasNotification: Bool
    let hasUrgentNotification: Bool
    let hasDecisionPoint: Bool
    let isSystemChromeNoise: Bool
    let isMediaOrImportantViewing: Bool
    let isPassiveReading: Bool
    let feedbackPenalty: Double
    let engagementBoost: Double
    let contextInterruptionPenalty: Double

    init(
        desktopContext: DesktopContextSnapshot,
        accessibilityTree: DesktopAccessibilityTreeSnapshot,
        feedback: SidekickSuggestionFeedbackSummary?,
        now: Date
    ) {
        let nodes = accessibilityTree.nodes
        let corpus = Self.corpus(desktopContext: desktopContext, nodes: nodes)
        let focusedNode = nodes.first { $0.focused == true }
        let editableNodes = nodes.filter(Self.isEditable)
        let focusedEditable = focusedNode.map(Self.isEditable) ?? false
        let focusedDraft = focusedNode.map { Self.isEditable($0) && Self.hasValue($0) } ?? false
        let isSystemChromeNoise = Self.containsAny(corpus, [
            "chrome is being controlled by automated test software",
            "remote debugging",
            "debugging infobar",
            "address and search bar",
            "tab group",
            "close tab",
        ])
        let hasError = Self.containsAny(corpus, [
            "error", "failed", "failure", "invalid", "blocked", "declined", "denied", "couldn't", "unable",
        ])
        let hasDialog = nodes.contains { node in
            Self.nodeContainsAny(node, ["dialog", "sheet", "modal", "alert"])
        }
        let hasNotification = Self.containsAny(corpus, [
            "notification", "unread", "message from", "reminder", "invite", "calendar", "missed",
        ])
        let hasUrgentNotification = hasNotification && Self.containsAny(corpus, [
            "urgent", "overdue", "due", "today", "now", "failed", "declined", "blocked",
        ])
        let staticTextCount = nodes.filter { node in
            Self.contains(node.role, "statictext") || Self.contains(node.roleDescription, "text")
        }.count
        let hasMedia = Self.containsAny(corpus, [
            "youtube", "video", "watch", "player", "playback", "stream", "lecture", "pause", "play",
        ])
        let browserOrReader = desktopContext.browser != nil
            || Self.containsAny(corpus, ["safari", "chrome", "arc", "reader"])
        let passiveReading = browserOrReader
            && staticTextCount >= 4
            && focusedEditable == false
            && hasError == false
            && hasDialog == false
            && hasNotification == false
        let decisionPoint = (
            hasDialog
                || hasNotification
                || editableNodes.isEmpty == false
        ) && Self.containsAnyDecisionPhrase(corpus, [
            "choose", "select", "continue", "cancel", "allow", "deny", "accept", "decline", "yes", "no",
            "submit", "send", "reply", "install", "update", "retry", "grant", "open settings",
        ])
        let meaningfulDialog = hasDialog
            && isSystemChromeNoise == false
            && (decisionPoint || hasError || hasNotification || editableNodes.isEmpty == false)

        self.isFocusedDraft = focusedDraft
        self.isFocusedInput = focusedEditable && focusedDraft == false
        self.hasForm = editableNodes.count >= 2
        self.hasDialog = hasDialog
        self.hasMeaningfulDialog = meaningfulDialog
        self.hasError = hasError
        self.hasNotification = hasNotification
        self.hasUrgentNotification = hasUrgentNotification
        self.hasDecisionPoint = decisionPoint
        self.isSystemChromeNoise = isSystemChromeNoise
        self.isMediaOrImportantViewing = hasMedia && focusedEditable == false && hasError == false
        self.isPassiveReading = passiveReading
        self.feedbackPenalty = min(
            0.40,
            Double(feedback?.ignores ?? 0) * 0.06
                + Double(feedback?.consecutiveIgnores ?? 0) * 0.12
                + Self.cooldownPenalty(feedback: feedback, now: now)
        )
        self.engagementBoost = min(0.18, Double(feedback?.engagements ?? 0) * 0.04)
        self.contextInterruptionPenalty = {
            if focusedDraft { return 0.28 }
            if focusedEditable { return 0.22 }
            if hasMedia { return 0.24 }
            if passiveReading { return 0.18 }
            if isSystemChromeNoise { return 0.18 }
            return 0
        }()
    }

    private static func cooldownPenalty(
        feedback: SidekickSuggestionFeedbackSummary?,
        now: Date
    ) -> Double {
        guard feedback?.shouldSuppress(now: now) == true else { return 0 }
        return 0.18
    }

    private static func corpus(
        desktopContext: DesktopContextSnapshot,
        nodes: [DesktopAccessibilityTreeSnapshot.Node]
    ) -> String {
        let contextParts = [
            desktopContext.app?.name,
            desktopContext.app?.bundleIdentifier,
            desktopContext.window?.title,
            desktopContext.window?.ownerName,
            desktopContext.browser?.title,
            desktopContext.browser?.url,
        ]
        let nodeParts = nodes.flatMap { node -> [String?] in
            [
                node.role,
                node.subrole,
                node.roleDescription,
                node.title,
                node.label,
                node.value,
                node.identifier,
                node.actions.joined(separator: " "),
            ]
        }
        return (contextParts + nodeParts)
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    private static func isEditable(_ node: DesktopAccessibilityTreeSnapshot.Node) -> Bool {
        let role = normalized(node.role)
        return role == "axtextarea"
            || role == "axtextfield"
            || role == "axcombobox"
            || role.contains("text area")
            || role.contains("text field")
    }

    private static func hasValue(_ node: DesktopAccessibilityTreeSnapshot.Node) -> Bool {
        normalized(node.value).isEmpty == false
    }

    private static func nodeContainsAny(
        _ node: DesktopAccessibilityTreeSnapshot.Node,
        _ needles: [String]
    ) -> Bool {
        let text = [
            node.role,
            node.subrole,
            node.roleDescription,
            node.title,
            node.label,
            node.value,
            node.identifier,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        return containsAny(text, needles)
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private static func containsAnyDecisionPhrase(_ value: String, _ needles: [String]) -> Bool {
        let tokens = Set(value.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.isEmpty == false })
        return needles.contains { needle in
            if needle.contains(" ") {
                return value.contains(needle)
            }
            return tokens.contains(needle)
        }
    }

    private static func contains(_ value: String?, _ needle: String) -> Bool {
        normalized(value).contains(needle.lowercased())
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
