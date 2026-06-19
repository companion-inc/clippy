import Foundation

public struct ClippyInvocationSuggestion: Equatable, Sendable {
    public let title: String
    public let prompt: String

    public init(title: String, prompt: String) {
        self.title = title
        self.prompt = prompt
    }
}

public enum ClippyInvocationSuggestions {
    public static func heading(for context: DesktopContextSnapshot) -> String {
        let subject: String
        if let url = context.browser?.url, URL(string: url)?.host != nil {
            subject = "this page"
        } else if let appName = context.app?.name, appName.isEmpty == false {
            subject = appName
        } else {
            subject = "this screen"
        }
        return "What should I do with \(subject)?"
    }

    public static func suggestions(for context: DesktopContextSnapshot) -> [ClippyInvocationSuggestion] {
        let bundle = context.app?.bundleIdentifier?.lowercased() ?? ""
        let app = context.app?.name.lowercased() ?? ""
        let title = context.window?.title?.lowercased() ?? context.browser?.title?.lowercased() ?? ""
        let url = context.browser?.url?.lowercased() ?? ""

        if isBrowser(bundle: bundle) {
            return browserSuggestions(title: title, url: url)
        }
        if containsAny(bundle + " " + app, ["terminal", "iterm", "warp"]) {
            return terminalSuggestions()
        }
        if containsAny(bundle + " " + app, ["xcode", "cursor", "visual studio code", "code", "zed"]) {
            return codingSuggestions()
        }
        if containsAny(bundle + " " + app, ["mail", "messages", "slack", "discord", "outlook"]) {
            return communicationSuggestions()
        }
        if containsAny(bundle + " " + app, ["finder"]) {
            return finderSuggestions()
        }
        if containsAny(bundle + " " + app, ["calendar"]) {
            return calendarSuggestions()
        }
        return genericSuggestions()
    }

    private static func browserSuggestions(title: String, url: String) -> [ClippyInvocationSuggestion] {
        var suggestions: [ClippyInvocationSuggestion] = [
            .init(
                title: "Explain this page",
                prompt: "Look at my current browser page and explain what matters here in a short answer."
            ),
            .init(
                title: "Show next click",
                prompt: "Look at my current browser page and point to the next useful thing to click. Do not click it for me."
            ),
        ]
        if containsAny(title + " " + url, ["form", "apply", "application", "signup", "sign up", "login", "checkout", "settings", "profile"]) {
            suggestions.append(.init(
                title: "Help fill this",
                prompt: "Help me fill out or complete the current page. Ask before submitting anything."
            ))
        } else {
            suggestions.append(.init(
                title: "Summarize it",
                prompt: "Summarize this page and tell me the most useful next action."
            ))
        }
        return suggestions
    }

    private static func terminalSuggestions() -> [ClippyInvocationSuggestion] {
        [
            .init(
                title: "Explain error",
                prompt: "Look at my current Terminal screen and explain the error plus the next command to try."
            ),
            .init(
                title: "Next command",
                prompt: "Look at my current Terminal screen and suggest the next command. Do not run it."
            ),
            .init(
                title: "Summarize output",
                prompt: "Summarize the current Terminal output and tell me what it means."
            ),
        ]
    }

    private static func codingSuggestions() -> [ClippyInvocationSuggestion] {
        [
            .init(
                title: "Explain code",
                prompt: "Look at the current code on my screen and explain the important part."
            ),
            .init(
                title: "Find the bug",
                prompt: "Look at the current code or error on my screen and find the likely bug."
            ),
            .init(
                title: "Next step",
                prompt: "Look at the current coding screen and suggest the next useful step."
            ),
        ]
    }

    private static func communicationSuggestions() -> [ClippyInvocationSuggestion] {
        [
            .init(
                title: "Draft reply",
                prompt: "Look at the current conversation or email and draft a reply. Do not send it."
            ),
            .init(
                title: "Summarize thread",
                prompt: "Summarize the current thread and list the action items."
            ),
            .init(
                title: "Tone check",
                prompt: "Help me write a concise response that fits the current conversation."
            ),
        ]
    }

    private static func finderSuggestions() -> [ClippyInvocationSuggestion] {
        [
            .init(
                title: "Explain folder",
                prompt: "Look at the current Finder window and explain what's in this folder."
            ),
            .init(
                title: "Find something",
                prompt: "Look at the current Finder window and help me find the file or folder I probably need."
            ),
            .init(
                title: "Organize this",
                prompt: "Look at the current Finder window and suggest a simple way to organize it."
            ),
        ]
    }

    private static func calendarSuggestions() -> [ClippyInvocationSuggestion] {
        [
            .init(
                title: "Prep me",
                prompt: "Look at my current calendar screen and help me prepare for what's next."
            ),
            .init(
                title: "Find conflicts",
                prompt: "Look at my current calendar screen and point out scheduling conflicts or tight spots."
            ),
            .init(
                title: "Summarize day",
                prompt: "Summarize the visible calendar and tell me what to focus on."
            ),
        ]
    }

    private static func genericSuggestions() -> [ClippyInvocationSuggestion] {
        [
            .init(
                title: "Explain this",
                prompt: "Look at my current screen and explain what matters here in a short answer."
            ),
            .init(
                title: "Show next click",
                prompt: "Look at my current screen and point to the next useful thing to click. Do not click it for me."
            ),
            .init(
                title: "What can I do?",
                prompt: "Look at my current screen and suggest three useful things you can help me do here."
            ),
        ]
    }

    private static func isBrowser(bundle: String) -> Bool {
        containsAny(bundle, ["safari", "chrome", "brave", "edgemac", "arc", "browser"])
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
