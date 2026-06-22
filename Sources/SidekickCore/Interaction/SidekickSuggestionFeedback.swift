import Foundation

public struct SidekickSuggestionFeedbackKey: Codable, Equatable, Hashable, Sendable {
    public let appIdentifier: String
    public let surface: String

    public init(appIdentifier: String, surface: String) {
        self.appIdentifier = appIdentifier
        self.surface = surface
    }

    public var storageKey: String {
        "\(appIdentifier)|\(surface)"
    }
}

public struct SidekickSuggestionFeedbackSummary: Equatable, Sendable {
    public let key: SidekickSuggestionFeedbackKey
    public let impressions: Int
    public let engagements: Int
    public let ignores: Int
    public let consecutiveIgnores: Int
    public let lastImpressionAt: Date?
    public let lastEngagementAt: Date?
    public let lastIgnoreAt: Date?
    public let suppressUntil: Date?

    public var hasHistory: Bool {
        impressions > 0 || engagements > 0 || ignores > 0
    }

    public func shouldSuppress(now: Date = Date()) -> Bool {
        guard let suppressUntil else { return false }
        return suppressUntil > now
    }

    public func promptBlock(now: Date = Date()) -> String? {
        guard hasHistory else { return nil }
        var lines = [
            "[Recent proactive suggestion feedback for this app/surface:",
            "- context: \(key.storageKey)",
            "- shown: \(impressions)",
            "- clicked or opened: \(engagements)",
            "- ignored by auto-hide: \(ignores)",
            "- consecutive ignores: \(consecutiveIgnores)",
        ]
        if let lastIgnoreAt {
            lines.append("- last ignored: \(Self.relativeSeconds(from: lastIgnoreAt, to: now))s ago")
        }
        if let suppressUntil, suppressUntil > now {
            lines.append("- cooldown remaining: \(Int(ceil(suppressUntil.timeIntervalSince(now))))s")
        }
        lines.append("- treat ignored proactive popups as negative feedback; only interrupt again for a materially new or higher-value state")
        lines.append("]")
        return lines.joined(separator: "\n")
    }

    private static func relativeSeconds(from date: Date, to now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(date)))
    }
}

public enum SidekickSuggestionFeedback {
    public static func contextKey(
        desktopContext: DesktopContextSnapshot,
        accessibilityTree: DesktopAccessibilityTreeSnapshot
    ) -> SidekickSuggestionFeedbackKey {
        let appIdentifier = clean(
            desktopContext.app?.bundleIdentifier
                ?? accessibilityTree.bundleIdentifier
                ?? desktopContext.app?.name
                ?? accessibilityTree.appName
        ) ?? "unknown-app"
        return SidekickSuggestionFeedbackKey(
            appIdentifier: appIdentifier,
            surface: surface(for: accessibilityTree)
        )
    }

    private static func surface(for tree: DesktopAccessibilityTreeSnapshot) -> String {
        let editableNodes = tree.nodes.filter(isEditable)
        let focusedNode = tree.nodes.first { $0.focused == true }
        let focusedEditable = focusedNode.map(isEditable) ?? false
        let focusedDraft = focusedNode.map { isEditable($0) && hasDraftValue($0) } ?? false
        let hasDraft = editableNodes.contains(where: hasDraftValue)
        let hasEditable = editableNodes.isEmpty == false
        let hasDialog = tree.nodes.contains { node in
            contains(node.role, "dialog")
                || contains(node.subrole, "dialog")
                || contains(node.roleDescription, "dialog")
                || contains(node.roleDescription, "sheet")
        }
        let hasError = tree.nodes.contains { node in
            contains(node.title, "error")
                || contains(node.label, "error")
                || contains(node.value, "error")
                || contains(node.title, "failed")
                || contains(node.label, "failed")
                || contains(node.value, "failed")
        }

        if focusedDraft { return "focused-draft" }
        if focusedEditable { return "focused-input" }
        if hasDraft { return "visible-draft" }
        if hasEditable { return "visible-input" }
        if hasError { return "error-state" }
        if hasDialog { return "dialog" }
        return "general"
    }

    private static func isEditable(_ node: DesktopAccessibilityTreeSnapshot.Node) -> Bool {
        guard let role = clean(node.role)?.lowercased() else { return false }
        return role == "axtextarea"
            || role == "axtextfield"
            || role == "axcombobox"
            || role.contains("text area")
            || role.contains("text field")
    }

    private static func hasDraftValue(_ node: DesktopAccessibilityTreeSnapshot.Node) -> Bool {
        clean(node.value)?.isEmpty == false
    }

    private static func contains(_ value: String?, _ needle: String) -> Bool {
        clean(value)?.localizedCaseInsensitiveContains(needle) ?? false
    }

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public final class SidekickSuggestionFeedbackStore {
    public static let defaultsKey = "SidekickSuggestionFeedbackRecords"

    private struct Record: Codable {
        var impressions = 0
        var engagements = 0
        var ignores = 0
        var consecutiveIgnores = 0
        var lastImpressionAt: TimeInterval?
        var lastEngagementAt: TimeInterval?
        var lastIgnoreAt: TimeInterval?
        var suppressUntil: TimeInterval?
    }

    private let defaults: UserDefaults
    private let defaultsKey: String

    public init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = SidekickSuggestionFeedbackStore.defaultsKey
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
    }

    public func summary(
        for key: SidekickSuggestionFeedbackKey,
        now _: Date = Date()
    ) -> SidekickSuggestionFeedbackSummary {
        summary(from: records()[key.storageKey] ?? Record(), key: key)
    }

    public func shouldSuppress(
        _ key: SidekickSuggestionFeedbackKey,
        now: Date = Date()
    ) -> Bool {
        summary(for: key, now: now).shouldSuppress(now: now)
    }

    @discardableResult
    public func recordImpression(
        for key: SidekickSuggestionFeedbackKey,
        now: Date = Date()
    ) -> SidekickSuggestionFeedbackSummary {
        mutate(key) { record in
            record.impressions += 1
            record.lastImpressionAt = now.timeIntervalSince1970
        }
    }

    @discardableResult
    public func recordEngagement(
        for key: SidekickSuggestionFeedbackKey,
        now: Date = Date()
    ) -> SidekickSuggestionFeedbackSummary {
        mutate(key) { record in
            record.engagements += 1
            record.consecutiveIgnores = 0
            record.suppressUntil = nil
            record.lastEngagementAt = now.timeIntervalSince1970
        }
    }

    @discardableResult
    public func recordIgnore(
        for key: SidekickSuggestionFeedbackKey,
        now: Date = Date()
    ) -> SidekickSuggestionFeedbackSummary {
        mutate(key) { record in
            record.ignores += 1
            record.consecutiveIgnores += 1
            record.lastIgnoreAt = now.timeIntervalSince1970
            record.suppressUntil = now.addingTimeInterval(
                Self.cooldownSeconds(afterConsecutiveIgnores: record.consecutiveIgnores)
            ).timeIntervalSince1970
        }
    }

    public static func cooldownSeconds(afterConsecutiveIgnores count: Int) -> TimeInterval {
        guard count > 0 else { return 0 }
        let base = 120.0
        let scaled = base * pow(2.0, Double(count - 1))
        return min(1_800.0, scaled)
    }

    private func mutate(
        _ key: SidekickSuggestionFeedbackKey,
        _ update: (inout Record) -> Void
    ) -> SidekickSuggestionFeedbackSummary {
        var current = records()
        var record = current[key.storageKey] ?? Record()
        update(&record)
        current[key.storageKey] = record
        save(current)
        return summary(from: record, key: key)
    }

    private func summary(
        from record: Record,
        key: SidekickSuggestionFeedbackKey
    ) -> SidekickSuggestionFeedbackSummary {
        SidekickSuggestionFeedbackSummary(
            key: key,
            impressions: record.impressions,
            engagements: record.engagements,
            ignores: record.ignores,
            consecutiveIgnores: record.consecutiveIgnores,
            lastImpressionAt: record.lastImpressionAt.map(Date.init(timeIntervalSince1970:)),
            lastEngagementAt: record.lastEngagementAt.map(Date.init(timeIntervalSince1970:)),
            lastIgnoreAt: record.lastIgnoreAt.map(Date.init(timeIntervalSince1970:)),
            suppressUntil: record.suppressUntil.map(Date.init(timeIntervalSince1970:))
        )
    }

    private func records() -> [String: Record] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func save(_ records: [String: Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
