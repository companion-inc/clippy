import Foundation
import CoreGraphics

/// On-screen grounding directives the agent can emit inline in its reply.
/// Clippy renders these by moving and gesturing with
/// its own body (and drawing outline/highlight overlays) — there is no synthetic cursor.
///
/// Tag formats:
///   [POINT:x,y:label]        [POINT:x,y:label:screenN]      [POINT:none]
///   [TARGET:x,y,r:label]     one click/commit Clippy can observe + recapture from
///   [HOVER:x,y,r:label]      a hover-reveal step
///   [HIGHLIGHT:x,y,r:label]  outline a work area for manual work
///   [SHAPE:kind:x1,y1;x2,y2;...:label]   kind in line|arrow|circle|curve|polygon
///
/// Coordinates are in the source screenshot's pixel space (top-left origin, y-down);
/// `GroundingDirector.screenPoint` maps them into global AppKit coordinates.
public enum GroundingTag: Equatable, Sendable {
    case point(CGPoint, label: String, screen: Int?)
    case target(CGPoint, radius: Double, label: String, screen: Int?)
    case hover(CGPoint, radius: Double, label: String, screen: Int?)
    case highlight(CGPoint, radius: Double, label: String, screen: Int?)
    case shape(kind: ShapeKind, points: [CGPoint], label: String, screen: Int?)
    /// Clippy performs one of its own animations to express what it's doing or feeling.
    case act(animation: String)

    public enum ShapeKind: String, Equatable, Sendable, CaseIterable {
        case line, arrow, circle, curve, polygon
    }

    /// The label Clippy shows in its speech bubble for this directive.
    public var label: String {
        switch self {
        case let .point(_, label, _),
             let .target(_, _, label, _),
             let .hover(_, _, label, _),
             let .highlight(_, _, label, _),
             let .shape(_, _, label, _):
            return label
        case let .act(animation):
            return animation
        }
    }

    /// One-based screenshot number from an optional `:screenN` suffix.
    public var screenNumber: Int? {
        switch self {
        case let .point(_, _, screen),
             let .target(_, _, _, screen),
             let .hover(_, _, _, screen),
             let .highlight(_, _, _, screen),
             let .shape(_, _, _, screen):
            return screen
        case .act:
            return nil
        }
    }

    /// The primary on-screen anchor Clippy should point at (first point for shapes).
    public var anchor: CGPoint? {
        switch self {
        case let .point(p, _, _),
             let .target(p, _, _, _),
             let .hover(p, _, _, _),
             let .highlight(p, _, _, _):
            return p
        case let .shape(_, points, _, _):
            return points.first
        case .act:
            return nil
        }
    }

    /// Whether this directive is a Swift-observable action Clippy should recapture after.
    public var isActionable: Bool {
        switch self {
        case .target, .hover: return true
        case .point, .highlight, .shape, .act: return false
        }
    }

    /// Whether this directive draws visible screen guidance. `[ACT]` changes
    /// Clippy's body animation, but it is not a screen grounding mark.
    public var isRenderableVisual: Bool {
        switch self {
        case .point, .target, .hover, .highlight, .shape: return true
        case .act: return false
        }
    }

    /// Map this tag's coordinates from the screenshot's pixel space (what the model
    /// emitted, having Read the image) into global AppKit screen space, so the overlay
    /// and Clippy's body land where the model actually meant. Radii scale with the
    /// image→screen ratio. `.act` has no coordinates and is returned unchanged.
    public func inScreenSpace(imageSize: CGSize, display: CGRect) -> GroundingTag {
        guard imageSize.width > 0, imageSize.height > 0 else { return self }
        let scale = Double(display.width / imageSize.width)
        func m(_ p: CGPoint) -> CGPoint {
            GroundingDirector.screenPoint(fromPixel: p, imageSize: imageSize, display: display)
        }
        switch self {
        case let .point(p, label, screen): return .point(m(p), label: label, screen: screen)
        case let .target(p, r, label, screen): return .target(m(p), radius: r * scale, label: label, screen: screen)
        case let .hover(p, r, label, screen): return .hover(m(p), radius: r * scale, label: label, screen: screen)
        case let .highlight(p, r, label, screen): return .highlight(m(p), radius: r * scale, label: label, screen: screen)
        case let .shape(kind, points, label, screen): return .shape(kind: kind, points: points.map(m), label: label, screen: screen)
        case .act: return self
        }
    }
}

/// An assistant reply split into the text Clippy speaks and the directives it acts on.
public struct GroundingDirectives: Equatable, Sendable {
    public let spokenText: String
    public let tags: [GroundingTag]

    public init(spokenText: String, tags: [GroundingTag]) {
        self.spokenText = spokenText
        self.tags = tags
    }
}

/// Parses Clippy grounding tags out of an assistant reply.
public enum GroundingParser {
    public static func parse(_ text: String) -> GroundingDirectives {
        GroundingDirectives(spokenText: strip(text), tags: tags(in: text))
    }

    /// Remove every grounding tag from `text` and tidy whitespace (for the bubble / TTS).
    public static func strip(_ text: String) -> String {
        let ns = text as NSString
        let cleaned = sanitizer.stringByReplacingMatches(
            in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return cleaned
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Like `strip`, but also hides a tag that is still being typed while the reply
    /// streams in — so a half-emitted `[POIN…` never flashes in the bubble before it
    /// closes. Drops a trailing, unclosed `[Tag…` (open bracket + optional tag name +
    /// optional partial `:args`, with no `]` yet), then strips any complete tags.
    public static func stripForStreaming(_ text: String) -> String {
        let withoutInProgress = text.replacingOccurrences(
            of: #"\s*[\[<][A-Za-z]*(?::[^\]>]*)?$"#, with: "", options: .regularExpression)
        return strip(withoutInProgress)
    }

    /// Extract directives in the order they appear in `text`.
    public static func tags(in text: String) -> [GroundingTag] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var found: [(Int, GroundingTag)] = []

        for m in pointRegex.matches(in: text, options: [], range: full) {
            guard let x = group(1, m, ns).flatMap({ Double($0) }),
                  let y = group(2, m, ns).flatMap({ Double($0) }) else {
                continue // [POINT:none] -> no directive
            }
            found.append((m.range.location, .point(
                CGPoint(x: x, y: y), label: group(3, m, ns) ?? "", screen: group(4, m, ns).flatMap { Int($0) })))
        }

        for m in regionRegex.matches(in: text, options: [], range: full) {
            guard let kind = group(1, m, ns)?.uppercased(),
                  let x = group(2, m, ns).flatMap({ Double($0) }),
                  let y = group(3, m, ns).flatMap({ Double($0) }),
                  let r = group(4, m, ns).flatMap({ Double($0) }) else { continue }
            let p = CGPoint(x: x, y: y)
            let label = group(5, m, ns) ?? ""
            let screen = group(6, m, ns).flatMap { Int($0) }
            let tag: GroundingTag
            switch kind {
            case "TARGET": tag = .target(p, radius: r, label: label, screen: screen)
            case "HOVER": tag = .hover(p, radius: r, label: label, screen: screen)
            default: tag = .highlight(p, radius: r, label: label, screen: screen)
            }
            found.append((m.range.location, tag))
        }

        for m in shapeRegex.matches(in: text, options: [], range: full) {
            guard let raw = group(1, m, ns)?.lowercased(),
                  let kind = GroundingTag.ShapeKind(rawValue: raw),
                  let pts = group(2, m, ns).map(points(from:)), !pts.isEmpty else { continue }
            found.append((m.range.location, .shape(
                kind: kind, points: pts, label: group(3, m, ns) ?? "", screen: group(4, m, ns).flatMap { Int($0) })))
        }

        for match in actRegex.matches(in: text, options: [], range: full) {
            if let name = group(1, match, ns) {
                found.append((match.range.location, .act(animation: name)))
            }
        }

        return found.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    /// Extract only a final `[POINT:...]` tag, matching the pointer contract used
    /// for normal assistant replies. `[POINT:none]` intentionally returns nil.
    public static func finalPointTag(in text: String) -> GroundingTag? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = finalPointRegex.firstMatch(in: text, options: [], range: full),
              let x = group(1, match, ns).flatMap({ Double($0) }),
              let y = group(2, match, ns).flatMap({ Double($0) }) else {
            return nil
        }
        return .point(
            CGPoint(x: x, y: y),
            label: group(3, match, ns) ?? "",
            screen: group(4, match, ns).flatMap { Int($0) }
        )
    }

    // MARK: - Patterns

    private static let pointRegex = re(#"[\[<]POINT:\s*(?:none|(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)(?:\s*:\s*([^\]:>\]]*?))?(?:\s*:\s*screen\s*(\d+))?)\s*[\]>]"#)
    private static let finalPointRegex = re(#"[\[<]POINT:\s*(?:none|(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)(?:\s*:\s*([^\]:>\]]*?))?(?:\s*:\s*screen\s*(\d+))?)\s*[\]>]\s*$"#)
    private static let regionRegex = re(#"[\[<](TARGET|HOVER|HIGHLIGHT):\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*:\s*([^\]:>\]]*?)(?:\s*:\s*screen\s*(\d+))?\s*[\]>]"#)
    private static let shapeRegex = re(#"[\[<]SHAPE:\s*(line|arrow|circle|curve|polygon)\s*:\s*([-0-9.,;\s]+?)\s*:\s*([^\]:>\]]*?)(?:\s*:\s*screen\s*(\d+))?\s*[\]>]"#)
    private static let actRegex = re(#"[\[<]ACT:\s*([A-Za-z0-9_]+)\s*[\]>]"#)
    private static let sanitizer = re(#"[\[<](?:POINT|HIGHLIGHT|SHAPE|TARGET|HOVER|ACT):[^\]>]*[\]>]"#)

    private static func re(_ pattern: String) -> NSRegularExpression {
        // Patterns are fixed literals; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func group(_ index: Int, _ match: NSTextCheckingResult, _ ns: NSString) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        let value = ns.substring(with: range).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func points(from raw: String) -> [CGPoint] {
        raw.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: ",")
            guard parts.count == 2,
                  let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let y = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return CGPoint(x: x, y: y)
        }
    }
}
