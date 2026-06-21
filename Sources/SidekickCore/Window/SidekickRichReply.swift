import Foundation

public struct SidekickRichReply: Equatable, Sendable {
    public struct ImageCard: Equatable, Sendable {
        public let caption: String
        public let imageURLString: String
        public let sourceTitle: String?
        public let sourceURLString: String?

        public init(
            caption: String,
            imageURLString: String,
            sourceTitle: String? = nil,
            sourceURLString: String? = nil
        ) {
            self.caption = caption
            self.imageURLString = imageURLString
            self.sourceTitle = sourceTitle
            self.sourceURLString = sourceURLString
        }
    }

    public struct Citation: Equatable, Sendable {
        public let title: String
        public let urlString: String

        public init(title: String, urlString: String) {
            self.title = title
            self.urlString = urlString
        }
    }

    public let text: String
    public let imageCards: [ImageCard]
    public let citations: [Citation]

    public init(text: String, imageCards: [ImageCard] = [], citations: [Citation] = []) {
        self.text = text
        self.imageCards = imageCards
        self.citations = citations
    }

    public var hasRichMedia: Bool {
        imageCards.isEmpty == false || citations.isEmpty == false
    }

    public static func parse(_ rawText: String) -> SidekickRichReply {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else {
            return SidekickRichReply(text: "")
        }

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let imageMatches = imageRegex.matches(in: text, range: fullRange)
        let linkMatches = markdownLinkMatches(in: text, excludingImageRanges: imageMatches.map(\.range))

        let citations = deduplicatedCitations(from: linkMatches, in: ns)
        let imageCards = imageMatches.map { match -> ImageCard in
            let caption = group(1, match, ns) ?? ""
            let imageURL = group(2, match, ns) ?? ""
            let source = sourceLink(forImageRange: match.range, linkMatches: linkMatches, text: text, ns: ns)
            return ImageCard(
                caption: caption,
                imageURLString: imageURL,
                sourceTitle: source?.title,
                sourceURLString: source?.urlString
            )
        }

        let displayText = strippedDisplayText(from: text)
        return SidekickRichReply(text: displayText, imageCards: imageCards, citations: citations)
    }

    private static func strippedDisplayText(from text: String) -> String {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let withoutImages = imageRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: fullRange,
            withTemplate: ""
        )
        let linkedText = linkRegex.stringByReplacingMatches(
            in: withoutImages,
            options: [],
            range: NSRange(location: 0, length: (withoutImages as NSString).length),
            withTemplate: "$1"
        )
        let cleanedLines = linkedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                let lower = line.lowercased()
                return line.isEmpty
                    || (lower.hasPrefix("image:") == false
                        && lower.hasPrefix("images:") == false
                        && lower.hasPrefix("source:") == false
                        && lower.hasPrefix("sources:") == false
                        && lower.hasPrefix("via:") == false
                        && lower.hasPrefix("credit:") == false
                        && lower.hasPrefix("credits:") == false)
            }

        return cleanedLines
            .joined(separator: "\n")
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markdownLinkMatches(
        in text: String,
        excludingImageRanges imageRanges: [NSRange]
    ) -> [NSTextCheckingResult] {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        return linkRegex.matches(in: text, range: fullRange).filter { match in
            let isImage = imageRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
            guard isImage == false else { return false }
            if match.range.location > 0 {
                let previous = ns.substring(with: NSRange(location: match.range.location - 1, length: 1))
                if previous == "!" { return false }
            }
            return true
        }
    }

    private static func deduplicatedCitations(from matches: [NSTextCheckingResult], in ns: NSString) -> [Citation] {
        var seen = Set<String>()
        var citations: [Citation] = []
        for match in matches {
            guard let title = group(1, match, ns),
                  let urlString = group(2, match, ns),
                  isDisplayableURL(urlString),
                  seen.insert(urlString).inserted else {
                continue
            }
            citations.append(Citation(title: title, urlString: urlString))
        }
        return citations
    }

    private static func sourceLink(
        forImageRange imageRange: NSRange,
        linkMatches: [NSTextCheckingResult],
        text: String,
        ns: NSString
    ) -> Citation? {
        let paragraph = paragraphRange(containing: imageRange, in: text)
        let candidates = linkMatches.filter { match in
            NSLocationInRange(match.range.location, paragraph) && match.range.location >= imageRange.upperBound
        }
        let sourceCandidate = candidates.first { match in
            let prefixRange = NSRange(location: paragraph.location, length: match.range.location - paragraph.location)
            let prefix = ns.substring(with: prefixRange).lowercased()
            return prefix.contains("source")
                || prefix.contains("via")
                || prefix.contains("credit")
                || prefix.contains("image")
        } ?? candidates.first

        guard let match = sourceCandidate,
              let title = group(1, match, ns),
              let urlString = group(2, match, ns),
              isDisplayableURL(urlString) else {
            return nil
        }
        return Citation(title: title, urlString: urlString)
    }

    private static func paragraphRange(containing range: NSRange, in text: String) -> NSRange {
        let ns = text as NSString
        var start = range.location
        while start > 0 {
            let previous = ns.substring(with: NSRange(location: start - 1, length: 1))
            if previous == "\n" {
                if start >= 2, ns.substring(with: NSRange(location: start - 2, length: 1)) == "\n" {
                    break
                }
            }
            start -= 1
        }

        var end = range.upperBound
        while end < ns.length {
            let current = ns.substring(with: NSRange(location: end, length: 1))
            if current == "\n" {
                if end + 1 < ns.length, ns.substring(with: NSRange(location: end + 1, length: 1)) == "\n" {
                    break
                }
            }
            end += 1
        }
        return NSRange(location: start, length: end - start)
    }

    private static func isDisplayableURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("https://")
            || lower.hasPrefix("http://")
            || lower.hasPrefix("file://")
            || lower.hasPrefix("/")
    }

    private static func group(_ index: Int, _ match: NSTextCheckingResult, _ ns: NSString) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        let value = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static let imageRegex = regex(#"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)
    private static let linkRegex = regex(#"\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [])
    }
}

private extension NSRange {
    var upperBound: Int { location + length }
}
