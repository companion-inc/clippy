import Foundation

public enum VoiceSpeechTags {
    public static let instant: [String] = [
        "[pause]",
        "[long-pause]",
        "[hum-tune]",
        "[laugh]",
        "[chuckle]",
        "[giggle]",
        "[cry]",
        "[tsk]",
        "[tongue-click]",
        "[lip-smack]",
        "[breath]",
        "[inhale]",
        "[exhale]",
        "[sigh]",
    ]

    public static let wrapping: [String] = [
        "soft",
        "whisper",
        "loud",
        "build-intensity",
        "decrease-intensity",
        "higher-pitch",
        "lower-pitch",
        "slow",
        "fast",
        "sing-song",
        "singing",
        "laugh-speak",
        "emphasis",
    ]

    public static let instruction = """
    xAI speech tags are available for natural spoken expression. Use them sparingly \
    for a Clippy-like delivery: bright, quick, crisp, upbeat, and lightly expressive. Prefer a lighter \
    desktop-buddy sound; avoid deep, soft, breathy, or whispery delivery unless the user asks for it. Instant tags: \
    \(instant.joined(separator: ", ")). Wrapping tags wrap complete phrases with \
    matching closing tags: \(wrapping.map { "<\($0)>" }.joined(separator: ", ")). \
    Use only these tags; SSML is not supported. Do not tag every sentence, and never \
    speak raw diagnostics, API keys, internal tool names, file paths, or URLs. Speech \
    tags are passed to text-to-speech but hidden from the bubble.
    """

    public static func strip(_ text: String) -> String {
        var cleaned = text
        for tag in instant {
            cleaned = cleaned.replacingOccurrences(of: tag, with: "")
        }
        for tag in wrapping {
            cleaned = cleaned.replacingOccurrences(
                of: #"</?\#(tag)>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return cleaned
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
