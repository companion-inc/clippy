import Foundation

public enum ClippyUserFacingError {
    public static func replacement(for technicalText: String, isError: Bool) -> String? {
        if isError {
            return message(for: technicalText)
        }
        if isTechnicalComputerUseFallback(technicalText) {
            return "I hit a local computer-control error. I saved the details in Clippy Logs."
        }
        return nil
    }

    public static func message(for technicalText: String) -> String {
        let lower = technicalText.lowercased()
        if containsAny(lower, ["cua", "computer-use", "mcp", "tool", "browser", "click", "type"]) {
            return "I hit a local computer-control error. I saved the details in Clippy Logs."
        }
        if containsAny(lower, ["codex", "app-server", "model", "stream"]) {
            return "I hit a local brain error. I saved the details in Clippy Logs."
        }
        return "I hit a local error. I saved the details in Clippy Logs."
    }

    public static func isTechnicalComputerUseFallback(_ text: String) -> Bool {
        let lower = text.lowercased()
        let mentionsInternalComputerUse = containsAny(lower, [
            "cua",
            "computer-use bridge",
            "computer use bridge",
            "mcp",
        ])
        let givesUpOrHandsOff = containsAny(lower, [
            "not connected",
            "isn't connected",
            "is not connected",
            "not available",
            "unavailable",
            "can't click",
            "cannot click",
            "can't type",
            "cannot type",
            "start the computer-use bridge",
            "start the computer use bridge",
            "start the bridge",
        ])
        return mentionsInternalComputerUse && givesUpOrHandsOff
    }

    private static func containsAny(_ lowercasedText: String, _ needles: [String]) -> Bool {
        needles.contains { lowercasedText.contains($0) }
    }
}
