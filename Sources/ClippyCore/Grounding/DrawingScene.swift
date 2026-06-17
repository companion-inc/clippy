import CoreGraphics
import Foundation

/// A vector annotation scene whose coordinates live in an explicit owner space.
/// Screen scenes use global AppKit coordinates; window scenes use coordinates
/// local to the captured app window and are reprojected while that window moves.
public struct DrawingScene: Equatable, Sendable {
    public let id: UUID
    public let anchor: DrawingAnchor
    public var objects: [DrawingObject]

    public init(id: UUID = UUID(), anchor: DrawingAnchor = .screen, objects: [DrawingObject]) {
        self.id = id
        self.anchor = anchor
        self.objects = objects
    }

    public init(marks: [AnnotationMark], anchor: DrawingAnchor = .screen) {
        self.init(anchor: anchor, objects: marks.compactMap { DrawingObject(mark: $0, anchor: anchor) })
    }

    public var isEmpty: Bool { objects.isEmpty }

    public var visualBeatDurations: [TimeInterval] {
        objects.map(\.visualBeatDuration)
    }

    public var visualBeatDuration: TimeInterval {
        visualBeatDurations.reduce(0, +)
    }

    public var tracksMovingWindow: Bool {
        if case .window = anchor { return true }
        return false
    }

    public var hidesWhenWindowIsNotFrontmost: Bool {
        if case .window = anchor { return true }
        return false
    }

    public func resolvedMarks(windowFrameProvider: (DrawingWindowAnchor) -> CGRect?) -> [AnnotationMark] {
        guard let frame = resolvedFrame(windowFrameProvider: windowFrameProvider) else { return [] }
        return objects.compactMap { $0.annotationMark(in: frame) }
    }

    public func primaryPoint(windowFrameProvider: (DrawingWindowAnchor) -> CGRect?) -> CGPoint? {
        guard let frame = resolvedFrame(windowFrameProvider: windowFrameProvider) else { return nil }
        return objects.lazy.compactMap { $0.primaryPoint(in: frame) }.first
    }

    public func resolvedFrame(windowFrameProvider: (DrawingWindowAnchor) -> CGRect?) -> CGRect? {
        switch anchor {
        case .screen:
            return .zero
        case let .window(window):
            return windowFrameProvider(window)
        }
    }

    public func withSequenceProgress(durations: [TimeInterval], elapsed: TimeInterval) -> DrawingScene {
        var remaining = max(0, elapsed)
        var visible: [DrawingObject] = []
        for index in objects.indices {
            let objectDuration = durations.indices.contains(index) ? durations[index] : objects[index].visualBeatDuration
            let duration = max(0.01, objectDuration)
            if remaining >= duration {
                visible.append(objects[index])
                remaining -= duration
            } else {
                visible.append(objects[index].withDrawProgress(CGFloat(remaining / duration)))
                break
            }
        }
        var copy = self
        copy.objects = visible
        return copy
    }
}

public enum DrawingAnchor: Equatable, Sendable {
    case screen
    case window(DrawingWindowAnchor)
}

public struct DrawingWindowAnchor: Equatable, Sendable {
    public let ownerProcessIdentifier: Int
    public let windowIdentifier: Int
    public let ownerName: String
    public let title: String?
    public let browserURL: String?
    public let initialFrame: CGRect

    public init(
        ownerProcessIdentifier: Int,
        windowIdentifier: Int,
        ownerName: String,
        title: String?,
        browserURL: String?,
        initialFrame: CGRect
    ) {
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.windowIdentifier = windowIdentifier
        self.ownerName = ownerName
        self.title = title
        self.browserURL = browserURL
        self.initialFrame = initialFrame
    }

    public init?(desktopContext: DesktopContextSnapshot) {
        guard let window = desktopContext.window,
              let frame = DesktopContextSnapshot.appKitFrame(for: window, screen: desktopContext.screen) else {
            return nil
        }
        self.init(
            ownerProcessIdentifier: window.ownerProcessIdentifier,
            windowIdentifier: window.windowIdentifier,
            ownerName: window.ownerName,
            title: window.title,
            browserURL: desktopContext.browser?.url,
            initialFrame: frame
        )
    }

    public func currentFrame() -> CGRect? {
        DesktopContextSnapshot.currentAppKitWindowFrame(
            ownerProcessIdentifier: ownerProcessIdentifier,
            windowIdentifier: windowIdentifier
        )
    }

    public func isFrontmost() -> Bool {
        DesktopContextSnapshot.isFrontmostWindow(
            ownerProcessIdentifier: ownerProcessIdentifier,
            windowIdentifier: windowIdentifier
        )
    }

    public func matches(_ window: DesktopContextSnapshot.WindowInfo) -> Bool {
        window.ownerProcessIdentifier == ownerProcessIdentifier
            && window.windowIdentifier == windowIdentifier
    }
}

public struct DrawingObject: Equatable, Sendable {
    public var geometry: DrawingGeometry
    public var drawProgress: CGFloat?

    public init(geometry: DrawingGeometry, drawProgress: CGFloat? = nil) {
        self.geometry = geometry
        self.drawProgress = drawProgress
    }

    public init?(mark: AnnotationMark, anchor: DrawingAnchor) {
        let referenceFrame: CGRect
        switch anchor {
        case .screen:
            referenceFrame = .zero
        case let .window(window):
            referenceFrame = window.initialFrame
        }
        guard let geometry = DrawingGeometry(mark: mark, referenceFrame: referenceFrame) else {
            return nil
        }
        self.init(geometry: geometry)
    }

    public var visualBeatDuration: TimeInterval {
        switch geometry {
        case let .path(points, shape):
            let length = Self.pathLength(points, closesPath: shape == .polygon)
            return TimeInterval(min(1.25, max(0.35, Double(length / 900))))
        case .ring, .region:
            return 0.18
        }
    }

    public func withDrawProgress(_ progress: CGFloat) -> DrawingObject {
        var copy = self
        copy.drawProgress = min(1, max(0, progress))
        return copy
    }

    public func annotationMark(in referenceFrame: CGRect) -> AnnotationMark? {
        geometry.annotationMark(in: referenceFrame, drawProgress: drawProgress)
    }

    public func primaryPoint(in referenceFrame: CGRect) -> CGPoint? {
        geometry.primaryPoint(in: referenceFrame)
    }

    private static func pathLength(_ points: [CGPoint], closesPath: Bool) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for pair in zip(points, points.dropFirst()) {
            total += hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
        if closesPath, let first = points.first, let last = points.last {
            total += hypot(first.x - last.x, first.y - last.y)
        }
        return total
    }
}

public enum DrawingGeometry: Equatable, Sendable {
    case ring(center: CGPoint, radius: CGFloat, kind: AnnotationMark.RingKind)
    case region(center: CGPoint, radius: CGFloat)
    case path(points: [CGPoint], shape: GroundingTag.ShapeKind)

    public init?(mark: AnnotationMark, referenceFrame: CGRect) {
        switch mark {
        case let .ring(center, radius, kind):
            self = .ring(center: center.local(to: referenceFrame), radius: radius, kind: kind)
        case let .region(center, radius):
            self = .region(center: center.local(to: referenceFrame), radius: radius)
        case let .path(points, shape):
            self = .path(points: points.map { $0.local(to: referenceFrame) }, shape: shape)
        case let .partialPath(points, shape, _):
            self = .path(points: points.map { $0.local(to: referenceFrame) }, shape: shape)
        }
    }

    public func annotationMark(in referenceFrame: CGRect, drawProgress: CGFloat?) -> AnnotationMark? {
        switch self {
        case let .ring(center, radius, kind):
            return .ring(center: center.global(from: referenceFrame), radius: radius, kind: kind)
        case let .region(center, radius):
            return .region(center: center.global(from: referenceFrame), radius: radius)
        case let .path(points, shape):
            let globalPoints = points.map { $0.global(from: referenceFrame) }
            guard let progress = drawProgress, progress < 0.999 else {
                return .path(points: globalPoints, shape: shape)
            }
            return .partialPath(points: globalPoints, shape: shape, progress: progress)
        }
    }

    public func primaryPoint(in referenceFrame: CGRect) -> CGPoint? {
        switch self {
        case let .ring(center, _, _), let .region(center, _):
            return center.global(from: referenceFrame)
        case let .path(points, _):
            return points.first?.global(from: referenceFrame)
        }
    }
}

private extension CGPoint {
    func local(to frame: CGRect) -> CGPoint {
        CGPoint(x: x - frame.minX, y: y - frame.minY)
    }

    func global(from frame: CGRect) -> CGPoint {
        CGPoint(x: x + frame.minX, y: y + frame.minY)
    }
}
