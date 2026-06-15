import Foundation
import CoreGraphics

/// Direction in screen/viewer coordinates, not in the sprite pack's internal naming.
/// The raw Clippy asset names are character-perspective for left/right, so keep the
/// translation explicit at the final animation boundary.
public enum ScreenPointingDirection: Equatable, Sendable {
    case screenUp
    case screenDown
    case screenLeft
    case screenRight
    case attention

    public var clippyAnimationName: String {
        switch self {
        case .screenUp: return "GestureUp"
        case .screenDown: return "GestureDown"
        case .screenLeft: return "GestureRight"
        case .screenRight: return "GestureLeft"
        case .attention: return "GetAttention"
        }
    }
}

/// Turns a parsed `GroundingTag` anchor into where Clippy should stand and which
/// gesture it should play. Pure geometry so it is unit-testable without a display.
public enum GroundingDirector {
    /// Map a screenshot pixel coordinate (top-left origin, y-down, in image pixels)
    /// into a global AppKit screen point (bottom-left origin, y-up). Mirrors the
    /// flip + display-offset Clippy applies so the gesture lands in the right place.
    public static func screenPoint(fromPixel pixel: CGPoint, imageSize: CGSize, display: CGRect) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return display.origin }
        let scaleX = display.width / imageSize.width
        let scaleY = display.height / imageSize.height
        let x = display.minX + pixel.x * scaleX
        let y = display.maxY - pixel.y * scaleY // flip: pixel top -> AppKit max-y
        return CGPoint(x: x, y: y)
    }

    /// Pick the visible screen direction from Clippy's body toward `target`
    /// (both in AppKit coordinates, y-up).
    public static func screenDirection(from clippyCenter: CGPoint, to target: CGPoint) -> ScreenPointingDirection {
        let dx = target.x - clippyCenter.x
        let dy = target.y - clippyCenter.y
        if abs(dx) < 28 && abs(dy) < 28 { return .attention }
        if abs(dx) >= abs(dy) { return dx >= 0 ? .screenRight : .screenLeft }
        return dy >= 0 ? .screenUp : .screenDown // y-up: target above Clippy -> point up
    }

    /// The actual Clippy asset animation that visually points from Clippy to `target`.
    public static func pointingAnimationName(from clippyCenter: CGPoint, to target: CGPoint) -> String {
        screenDirection(from: clippyCenter, to: target).clippyAnimationName
    }

    /// Where Clippy's window origin should go so it sits beside `target` without
    /// covering it, clamped to the visible frame.
    public static func parkOrigin(
        beside target: CGPoint,
        clippySize: CGSize,
        in visibleFrame: CGRect,
        gap: CGFloat = 36
    ) -> CGPoint {
        // Prefer standing to the left of the target; flip to the right if there's no room.
        var x = target.x - clippySize.width - gap
        if x < visibleFrame.minX { x = target.x + gap }
        var y = target.y - clippySize.height / 2
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - clippySize.width)
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - clippySize.height)
        return CGPoint(x: x, y: y)
    }
}
