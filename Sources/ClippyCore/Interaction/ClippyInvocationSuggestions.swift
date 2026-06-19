import Foundation

public struct ClippyInvocationSuggestion: Equatable, Sendable {
    public let title: String
    public let prompt: String

    public init(title: String, prompt: String) {
        self.title = title
        self.prompt = prompt
    }
}

public struct ClippyInvocationRecommendation: Equatable, Sendable {
    public let message: String
    public let suggestions: [ClippyInvocationSuggestion]

    public init(message: String, suggestions: [ClippyInvocationSuggestion]) {
        self.message = message
        self.suggestions = suggestions
    }
}

public enum ClippyInvocationSuggestions {
    public static let manualInputTitle = "Something else"

    public static func recommendationPrompt() -> String {
        """
        [Clippy double-click option picker]
        The user double-clicked Clippy. This is an intentional invocation, but the user's exact intention may not be clear.
        Look at the current screen screenshot and desktop metadata, infer why the user probably invoked Clippy right now, then write the menu Clippy should show: one short bubble line and exactly 3 useful things Clippy could do here to help the user.

        Return only a JSON object. No markdown, no prose, no visual tags.
        The object must have:
        - "message": the exact short Clippy speech-bubble line above the options. It should acknowledge the likely situation or intent, not name the app generically.
        - "options": exactly 3 option objects

        Each option object must have:
        - "title": a short menu label, 24 characters or fewer
        - "prompt": the exact instruction Clippy should run if the user picks it

        Pick options by intent, not by app category. Prefer the actions a user would plausibly want after summoning Clippy on this exact screen: continue stuck work, explain the confusing part, fill or draft visible content, point to the next control, summarize only when that is clearly useful, or help decide between visible choices.
        Avoid generic screen descriptions, generic app-name headings, and broad choices that could apply anywhere. Do not include a manual "something else" option; the app adds that separately. Do not include provider names or implementation details.
        For actions that send, delete, purchase, submit, or change accounts, make the prompt draft or inspect first and ask before committing.
        Example shape:
        {"message":"Looks like a form. Want me to help?","options":[{"title":"Fill this form","prompt":"Use the current screen to help me fill this form. Ask before submitting anything."}]}
        """
    }

    public static func parseRecommendation(from text: String, limit: Int = 3) -> ClippyInvocationRecommendation? {
        guard let data = jsonObjectData(in: text),
              let decoded = try? JSONDecoder().decode(RecommendationEnvelope.self, from: data),
              let message = cleanMessage(decoded.message)
        else {
            return nil
        }
        let options = decoded.options ?? []
        var seen = Set<String>()
        let suggestions: [ClippyInvocationSuggestion] = options.compactMap { dto -> ClippyInvocationSuggestion? in
            guard let title = cleanTitle(dto.title),
                  let prompt = cleanPrompt(dto.prompt)
            else {
                return nil
            }
            let key = title.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return ClippyInvocationSuggestion(title: title, prompt: prompt)
        }
        let limited = Array(suggestions.prefix(limit))

        guard limited.isEmpty == false else { return nil }
        return ClippyInvocationRecommendation(message: message, suggestions: limited)
    }

    private struct RecommendationEnvelope: Decodable {
        let message: String
        let options: [RecommendationDTO]?
    }

    private struct RecommendationDTO: Decodable {
        let title: String
        let prompt: String
    }

    private static func cleanTitle(_ raw: String) -> String? {
        var title = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^\s*[-*•\d.)]+\s*"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        title = String(title.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else { return nil }
        return title
    }

    private static func cleanMessage(_ raw: String) -> String? {
        let message = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard message.isEmpty == false else { return nil }
        return String(message.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanPrompt(_ raw: String) -> String? {
        let prompt = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard prompt.isEmpty == false else { return nil }
        return prompt
    }

    private static func jsonObjectData(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var isEscaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index]).data(using: .utf8)
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
