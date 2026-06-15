import Foundation
import CoreGraphics

/// The Clippy body animation used to point in a given direction. These are real
/// animation names in the committed Clippy pack (`character.json`), so Clippy points
/// with its own body instead of a synthetic cursor.
public enum ClippyPointGesture: String, Equatable, Sendable {
    case up = "GestureUp"
    case down = "GestureDown"
    case left = "GestureLeft"
    case right = "GestureRight"
    case attention = "GetAttention"
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

    /// Pick the gesture that points from Clippy's body toward `target`
    /// (both in AppKit coordinates, y-up).
    public static func gesture(from clippyCenter: CGPoint, to target: CGPoint) -> ClippyPointGesture {
        let dx = target.x - clippyCenter.x
        let dy = target.y - clippyCenter.y
        if abs(dx) < 28 && abs(dy) < 28 { return .attention }
        if abs(dx) >= abs(dy) { return dx >= 0 ? .right : .left }
        return dy >= 0 ? .up : .down // y-up: target above Clippy -> point up
    }

    /// Where Clippy's window origin should go so it sits beside `target` without
    /// covering it, clamped to the visible frame.
    public static func parkOrigin(
        beside target: CGPoint,
        mascotSize: CGSize,
        in visibleFrame: CGRect,
        gap: CGFloat = 36
    ) -> CGPoint {
        // Prefer standing to the left of the target; flip to the right if there's no room.
        var x = target.x - mascotSize.width - gap
        if x < visibleFrame.minX { x = target.x + gap }
        var y = target.y - mascotSize.height / 2
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - mascotSize.width)
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - mascotSize.height)
        return CGPoint(x: x, y: y)
    }
}
