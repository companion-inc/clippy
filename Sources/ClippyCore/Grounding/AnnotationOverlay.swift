import AppKit
import CoreGraphics

/// A resolved drawing instruction in global screen coordinates (y-up).
public enum AnnotationMark: Equatable, Sendable {
    case dot(center: CGPoint, progress: CGFloat)
    case ring(center: CGPoint, radius: CGFloat, kind: RingKind)
    case region(center: CGPoint, radius: CGFloat)
    case path(points: [CGPoint], shape: GroundingTag.ShapeKind)
    case partialPath(points: [CGPoint], shape: GroundingTag.ShapeKind, progress: CGFloat)

    public enum RingKind: Equatable, Sendable { case target, hover }

    /// Build a mark from a grounding tag whose coordinates are already in screen space.
    /// `POINT` gets a small precision dot; Clippy's own body remains the pointer.
    public init?(tag: GroundingTag) {
        switch tag {
        case let .point(p, _, _): self = .dot(center: p, progress: 1)
        case let .target(p, r, _, _): self = .ring(center: p, radius: CGFloat(r), kind: .target)
        case let .hover(p, r, _, _): self = .ring(center: p, radius: CGFloat(r), kind: .hover)
        case let .highlight(p, r, _, _): self = .region(center: p, radius: CGFloat(r))
        case let .shape(kind, pts, _, _): self = .path(points: pts, shape: kind)
        case .act: return nil
        }
    }
}

/// Borderless, transparent, click-through overlay that draws Clippy's on-screen marks
/// (point dots, target/hover rings, highlight outlines, shape paths) in global screen coordinates.
/// Clippy's body is the visible pointer; this overlay provides precise Clippy-style ink.
@MainActor
public final class AnnotationOverlayWindow {
    private let window: NSWindow
    private let drawView: AnnotationDrawView
    private var animationTimer: Timer?
    private var trackingTimer: Timer?

    public init() {
        let frame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        drawView = AnnotationDrawView(frame: CGRect(origin: .zero, size: frame.size))
        window.contentView = drawView
    }

    /// Draw `marks` (global screen coordinates). Empty clears and hides the overlay.
    public func show(_ marks: [AnnotationMark], on screen: NSScreen? = nil) {
        show(DrawingScene(marks: marks), on: screen)
    }

    /// Draw a spatial scene. Empty clears and hides the overlay.
    public func show(_ scene: DrawingScene, on screen: NSScreen? = nil) {
        animationTimer?.invalidate()
        animationTimer = nil
        trackingTimer?.invalidate()
        trackingTimer = nil
        let frame = (screen ?? NSScreen.main)?.frame ?? window.frame
        window.orderOut(nil)
        window.setFrame(frame, display: false)
        drawView.frame = CGRect(origin: .zero, size: frame.size)
        drawView.screenOrigin = frame.origin
        drawView.backgroundSampler = scene.isEmpty ? nil : AnnotationBackgroundSampler(screen: screen ?? NSScreen.main)
        drawView.scene = scene
        drawView.marks = []
        drawView.needsDisplay = true
        if scene.isEmpty {
            window.orderOut(nil)
        } else {
            updateWindowVisibility(for: scene)
            startTrackingIfNeeded(for: scene)
        }
    }

    /// Draw marks as Clippy visual beats: shape paths reveal over time, and
    /// multiple marks arrive in order instead of appearing as one finished overlay.
    public func showSequence(_ marks: [AnnotationMark], on screen: NSScreen? = nil) {
        showSequence(DrawingScene(marks: marks), on: screen)
    }

    /// Draw a spatial scene as Clippy visual beats.
    public func showSequence(_ scene: DrawingScene, on screen: NSScreen? = nil) {
        animationTimer?.invalidate()
        animationTimer = nil
        trackingTimer?.invalidate()
        trackingTimer = nil

        let frame = (screen ?? NSScreen.main)?.frame ?? window.frame
        window.orderOut(nil)
        window.setFrame(frame, display: false)
        drawView.frame = CGRect(origin: .zero, size: frame.size)
        drawView.screenOrigin = frame.origin
        drawView.backgroundSampler = scene.isEmpty ? nil : AnnotationBackgroundSampler(screen: screen ?? NSScreen.main)

        guard !scene.isEmpty else {
            drawView.scene = nil
            drawView.marks = []
            drawView.needsDisplay = true
            window.orderOut(nil)
            return
        }

        updateWindowVisibility(for: scene)
        let durations = scene.visualBeatDurations
        let totalDuration = durations.reduce(0, +)
        let start = ProcessInfo.processInfo.systemUptime

        renderSequenceFrame(scene: scene, durations: durations, elapsed: 0)
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                if elapsed >= totalDuration {
                    timer.invalidate()
                    if self.animationTimer === timer {
                        self.animationTimer = nil
                    }
                    guard self.updateWindowVisibility(for: scene) else {
                        self.startTrackingIfNeeded(for: scene)
                        return
                    }
                    self.drawView.scene = scene
                    self.drawView.marks = []
                    self.drawView.needsDisplay = true
                    self.startTrackingIfNeeded(for: scene)
                } else {
                    self.renderSequenceFrame(scene: scene, durations: durations, elapsed: elapsed)
                }
            }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func clear() {
        show([])
    }

    private func renderSequenceFrame(
        scene: DrawingScene,
        durations: [TimeInterval],
        elapsed: TimeInterval
    ) {
        guard updateWindowVisibility(for: scene) else { return }
        drawView.scene = scene.withSequenceProgress(durations: durations, elapsed: elapsed)
        drawView.marks = []
        drawView.needsDisplay = true
    }

    private func startTrackingIfNeeded(for scene: DrawingScene) {
        guard scene.tracksMovingWindow else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.refreshTrackedScene(scene)
            }
        }
        trackingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshTrackedScene(_ scene: DrawingScene) {
        guard updateWindowVisibility(for: scene) else { return }
        if let frame = scene.resolvedFrame(windowFrameProvider: { $0.currentFrame() }),
           let screen = ScreenPerception.screen(containing: frame),
           window.frame != screen.frame {
            window.setFrame(screen.frame, display: false)
            drawView.frame = CGRect(origin: .zero, size: screen.frame.size)
            drawView.screenOrigin = screen.frame.origin
            drawView.backgroundSampler = AnnotationBackgroundSampler(screen: screen)
        }
        drawView.needsDisplay = true
    }

    @discardableResult
    private func updateWindowVisibility(for scene: DrawingScene) -> Bool {
        if case let .window(anchor) = scene.anchor,
           anchor.isFrontmost() == false {
            window.orderOut(nil)
            return false
        }
        if scene.isEmpty == false, window.isVisible == false {
            window.orderFrontRegardless()
        }
        return true
    }
}

extension AnnotationMark {
    public var visualBeatDuration: TimeInterval {
        switch self {
        case .dot:
            return 0.22
        case let .path(points, shape),
             let .partialPath(points, shape, _):
            let length = Self.pathLength(points, closesPath: shape == .polygon)
            return TimeInterval(min(1.25, max(0.35, Double(length / 900))))
        case .ring, .region:
            return 0.18
        }
    }

    public func withDrawProgress(_ progress: CGFloat) -> AnnotationMark {
        let clamped = min(1, max(0, progress))
        switch self {
        case let .dot(center, _):
            return .dot(center: center, progress: clamped)
        case let .path(points, shape):
            return .partialPath(points: points, shape: shape, progress: clamped)
        case let .partialPath(points, shape, _):
            return .partialPath(points: points, shape: shape, progress: clamped)
        case .ring, .region:
            return clamped >= 1 ? self : self
        }
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

@MainActor
final class AnnotationDrawView: NSView {
    var marks: [AnnotationMark] = []
    var scene: DrawingScene?
    var screenOrigin: CGPoint = .zero
    var backgroundSampler: AnnotationBackgroundSampler?
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    private let markScale: CGFloat = 1

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(globalPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(globalPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(globalPoint(for: event))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let resolvedMarks = scene?.resolvedMarks(windowFrameProvider: { $0.currentFrame() }) ?? marks
        for mark in resolvedMarks {
            switch mark {
            case let .dot(center, progress):
                let c = local(center)
                drawPointDot(ctx, center: c, palette: palette(around: [center]), progress: progress)
            case let .ring(center, radius, kind):
                let c = local(center)
                let scaledRadius = radius * markScale
                let rect = CGRect(
                    x: c.x - scaledRadius,
                    y: c.y - scaledRadius,
                    width: scaledRadius * 2,
                    height: scaledRadius * 2
                )
                let palette = palette(around: [center])
                drawRing(ctx, rect: rect, palette: palette, fill: true, dashed: kind == .hover)
                drawCrosshair(
                    ctx,
                    center: c,
                    radius: min(max(scaledRadius * 0.28, 8 * markScale), 16 * markScale),
                    palette: palette,
                    dashed: kind == .hover
                )
            case let .region(center, radius):
                let c = local(center)
                let scaledRadius = radius * markScale
                let rect = CGRect(
                    x: c.x - scaledRadius,
                    y: c.y - scaledRadius,
                    width: scaledRadius * 2,
                    height: scaledRadius * 2
                )
                drawRegion(
                    ctx,
                    rect: rect,
                    palette: palette(around: regionSamplePoints(center: center, radius: scaledRadius)),
                    fill: false
                )
            case let .path(points, shape):
                let pts = points.map(local)
                guard let first = pts.first else { break }
                let palette = palette(around: points)
                if shape == .circle {
                    let r = circleRadius(points: pts)
                    drawRing(
                        ctx,
                        rect: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2),
                        palette: palette,
                        fill: true,
                        dashed: false
                    )
                    break
                }
                drawPath(ctx, points: pts, shape: shape, palette: palette)
                if shape == .arrow, pts.count >= 2 {
                    drawArrowHead(ctx, from: pts[pts.count - 2], to: pts[pts.count - 1], palette: palette)
                }
            case let .partialPath(points, shape, progress):
                let pts = points.map(local)
                guard let first = pts.first else { break }
                let palette = palette(around: points)
                if shape == .circle {
                    let r = circleRadius(points: pts)
                    drawRing(
                        ctx,
                        rect: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2),
                        palette: palette,
                        fill: true,
                        dashed: false
                    )
                    break
                }
                let visible = partialPathPoints(pts, closesPath: shape == .polygon, progress: progress)
                let finished = progress >= 0.999
                drawPath(ctx, points: finished ? pts : visible, shape: finished ? shape : .line, palette: palette)
                if shape == .arrow, visible.count >= 2 {
                    drawArrowHead(ctx, from: visible[visible.count - 2], to: visible[visible.count - 1], palette: palette)
                }
            }
        }
    }

    private func palette(around points: [CGPoint]) -> AnnotationPalette {
        let luminance = backgroundSampler?.averageLuminance(around: points)
        return AnnotationPalette(luminance: luminance, fallbackAppearance: effectiveAppearance)
    }

    private func regionSamplePoints(center: CGPoint, radius: CGFloat) -> [CGPoint] {
        [
            center,
            CGPoint(x: center.x - radius, y: center.y - radius),
            CGPoint(x: center.x + radius, y: center.y - radius),
            CGPoint(x: center.x - radius, y: center.y + radius),
            CGPoint(x: center.x + radius, y: center.y + radius),
        ]
    }

    private func circleRadius(points: [CGPoint]) -> CGFloat {
        guard let center = points.first else { return 32 * markScale }
        guard points.count >= 2 else { return 32 * markScale }
        let edge = points[1]
        return max(8 * markScale, hypot(edge.x - center.x, edge.y - center.y))
    }

    private func drawRing(_ ctx: CGContext, rect: CGRect, palette: AnnotationPalette, fill: Bool, dashed: Bool) {
        let path = CGPath(ellipseIn: rect.standardized.insetBy(dx: 1, dy: 1), transform: nil)
        if fill {
            ctx.setFillColor(palette.primary.withAlphaComponent(0.16).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
        if let backing = palette.backing {
            strokePath(ctx, path: path, color: backing, width: 6 * markScale, dashed: dashed)
            strokePath(ctx, path: path, color: palette.primary, width: 3 * markScale, dashed: dashed)
        } else {
            strokePath(ctx, path: path, color: palette.primary, width: 4 * markScale, dashed: dashed)
        }
    }

    private func drawPointDot(_ ctx: CGContext, center: CGPoint, palette: AnnotationPalette, progress: CGFloat) {
        let clamped = min(1, max(0, progress))
        let pulse = 1 - clamped
        let outerRadius = (13 + 7 * pulse) * markScale
        let innerRadius = 6 * markScale
        let outer = CGRect(
            x: center.x - outerRadius,
            y: center.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        )

        ctx.saveGState()
        ctx.setAlpha(0.40 + 0.25 * pulse)
        let outerPath = CGPath(ellipseIn: outer.standardized, transform: nil)
        strokePath(ctx, path: outerPath, color: palette.primary, width: 3 * markScale)
        ctx.restoreGState()

        let inner = CGRect(
            x: center.x - innerRadius,
            y: center.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )
        let innerPath = CGPath(ellipseIn: inner.standardized, transform: nil)
        ctx.setFillColor(palette.primary.withAlphaComponent(0.24).cgColor)
        ctx.addPath(innerPath)
        ctx.fillPath()

        if let backing = palette.backing {
            strokePath(ctx, path: innerPath, color: backing.withAlphaComponent(0.55), width: 2 * markScale)
            strokePath(ctx, path: innerPath, color: palette.primary, width: 1.5 * markScale)
        } else {
            strokePath(ctx, path: innerPath, color: palette.primary, width: 2 * markScale)
        }
    }

    private func drawRegion(_ ctx: CGContext, rect: CGRect, palette: AnnotationPalette, fill: Bool) {
        let r = rect.standardized.insetBy(dx: 1, dy: 1)
        let corner = min(16 * markScale, max(4, min(r.width, r.height) * 0.18))
        let path = CGPath(roundedRect: r, cornerWidth: corner, cornerHeight: corner, transform: nil)
        if fill {
            ctx.setFillColor(palette.primary.withAlphaComponent(0.12).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
        if let backing = palette.backing {
            strokePath(ctx, path: path, color: backing, width: 6 * markScale)
            strokePath(ctx, path: path, color: palette.primary, width: 3 * markScale)
        } else {
            strokePath(ctx, path: path, color: palette.primary, width: 4 * markScale)
        }
    }

    private func drawCrosshair(_ ctx: CGContext, center: CGPoint, radius: CGFloat, palette: AnnotationPalette, dashed: Bool) {
        ctx.saveGState()
        if dashed {
            ctx.setLineDash(phase: 0, lengths: [4 * markScale, 3 * markScale])
        }
        drawLine(ctx, from: CGPoint(x: center.x - radius, y: center.y), to: CGPoint(x: center.x + radius, y: center.y), palette: palette)
        drawLine(ctx, from: CGPoint(x: center.x, y: center.y - radius), to: CGPoint(x: center.x, y: center.y + radius), palette: palette)
        ctx.restoreGState()
    }

    private func drawPath(_ ctx: CGContext, points: [CGPoint], shape: GroundingTag.ShapeKind, palette: AnnotationPalette) {
        drawPathStroke(ctx, points: points, shape: shape, color: palette.inkBacking, width: 8 * markScale)
        drawPathStroke(ctx, points: points, shape: shape, color: palette.primary, width: 4 * markScale)
    }

    private func drawLine(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, palette: AnnotationPalette) {
        drawPathStroke(ctx, points: [a, b], shape: .line, color: palette.inkBacking, width: 7 * markScale)
        drawPathStroke(ctx, points: [a, b], shape: .line, color: palette.primary, width: 3.5 * markScale)
    }

    private func strokePath(_ ctx: CGContext, path: CGPath, color: NSColor, width: CGFloat, dashed: Bool = false) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(width)
        ctx.setStrokeColor(color.cgColor)
        if dashed {
            ctx.setLineDash(phase: 0, lengths: [6 * markScale, 4 * markScale])
        }
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func partialPathPoints(_ points: [CGPoint], closesPath: Bool, progress: CGFloat) -> [CGPoint] {
        guard points.count > 1 else { return points }
        let clamped = min(1, max(0, progress))
        var segments = Array(zip(points, points.dropFirst()))
        if closesPath, let first = points.first, let last = points.last {
            segments.append((last, first))
        }
        let total = segments.reduce(CGFloat(0)) { partial, segment in
            partial + hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y)
        }
        guard total > 0 else { return [points[0]] }

        var remaining = total * clamped
        var visible = [points[0]]
        for (start, end) in segments {
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 0 else { continue }
            if remaining >= length {
                visible.append(end)
                remaining -= length
            } else {
                let t = remaining / length
                visible.append(CGPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t
                ))
                break
            }
        }
        return visible
    }

    private func drawPathStroke(
        _ ctx: CGContext,
        points: [CGPoint],
        shape: GroundingTag.ShapeKind,
        color: NSColor,
        width: CGFloat
    ) {
        guard let first = points.first else { return }
        ctx.setLineWidth(width)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        ctx.move(to: first)
        if shape == .curve, points.count > 2 {
            let rest = Array(points.dropFirst())
            for index in rest.indices {
                let current = rest[index]
                if index == rest.indices.last {
                    ctx.addLine(to: current)
                } else {
                    let next = rest[index + 1]
                    let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                    ctx.addQuadCurve(to: mid, control: current)
                }
            }
        } else {
            for p in points.dropFirst() {
                ctx.addLine(to: p)
            }
        }
        if shape == .polygon {
            ctx.closePath()
        }
        ctx.strokePath()
    }

    private func drawArrowHead(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, palette: AnnotationPalette) {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let len: CGFloat = 18 * markScale
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: b.x - len * cos(angle - spread), y: b.y - len * sin(angle - spread))
        let right = CGPoint(x: b.x - len * cos(angle + spread), y: b.y - len * sin(angle + spread))
        if let backing = palette.backing {
            ctx.setFillColor(backing.cgColor)
            fillTriangle(ctx, a: b, b: left, c: right)
            let innerLen = len - 5
            let innerLeft = CGPoint(x: b.x - innerLen * cos(angle - spread), y: b.y - innerLen * sin(angle - spread))
            let innerRight = CGPoint(x: b.x - innerLen * cos(angle + spread), y: b.y - innerLen * sin(angle + spread))
            ctx.setFillColor(palette.primary.cgColor)
            fillTriangle(ctx, a: b, b: innerLeft, c: innerRight)
        } else {
            ctx.setFillColor(palette.primary.cgColor)
            fillTriangle(ctx, a: b, b: left, c: right)
        }
    }

    private func fillTriangle(_ ctx: CGContext, a: CGPoint, b: CGPoint, c: CGPoint) {
        ctx.beginPath()
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.addLine(to: c)
        ctx.closePath()
        ctx.fillPath()
    }

    private func local(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - screenOrigin.x, y: p.y - screenOrigin.y)
    }

    private func globalPoint(for event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + screenOrigin.x, y: local.y + screenOrigin.y)
    }
}

public struct UserScreenAnnotation: Equatable, Sendable {
    public let screenIndex: Int
    public let screenFrame: CGRect
    public let strokes: [[CGPoint]]

    public init(screenIndex: Int, screenFrame: CGRect, strokes: [[CGPoint]]) {
        self.screenIndex = screenIndex
        self.screenFrame = screenFrame
        self.strokes = strokes.map { Self.simplified($0) }.filter { $0.count >= 2 }
    }

    public var isEmpty: Bool { strokes.isEmpty }

    public var marks: [AnnotationMark] {
        strokes.map { .path(points: $0, shape: .curve) }
    }

    public var scene: DrawingScene {
        DrawingScene(marks: marks)
    }

    public func promptBlock(for screenshots: [ScreenPerception.Screenshot]) -> String? {
        guard !strokes.isEmpty else { return nil }
        let screenshot = screenshots.first { $0.screenIndex == screenIndex && $0.screenFrame == screenFrame }
            ?? screenshots.first { $0.screenIndex == screenIndex }
        guard let screenshot else {
            return fallbackPromptBlock()
        }
        let lines = strokes.enumerated().map { index, stroke -> String in
            let points = Self.sampled(stroke, maxPoints: 48).map {
                let pixel = GroundingDirector.pixelPoint(
                    fromScreen: $0,
                    imageSize: screenshot.pixelSize,
                    display: screenshot.screenFrame
                )
                return "\(Int(pixel.x.rounded())),\(Int(pixel.y.rounded()))"
            }.joined(separator: ";")
            return "Stroke \(index + 1) on screen\(screenshot.screenIndex + 1): \(points)"
        }
        return """
        [User screen annotations]
        The user drew \(strokes.count) freehand stroke(s) before this question. Treat these as user-authored yellow ink over the current screenshot, used to point out what they mean by "this", "that", or "what do you think". Do not call them Clippy's own marks.
        \(lines.joined(separator: "\n"))
        """
    }

    private func fallbackPromptBlock() -> String {
        let lines = strokes.enumerated().map { index, stroke -> String in
            let points = Self.sampled(stroke, maxPoints: 48).map {
                "\(Int($0.x.rounded())),\(Int($0.y.rounded()))"
            }.joined(separator: ";")
            return "Stroke \(index + 1) AppKit screen points: \(points)"
        }
        return """
        [User screen annotations]
        The user drew \(strokes.count) freehand stroke(s) before this question. A matching screenshot was not available, so coordinates are AppKit screen points.
        \(lines.joined(separator: "\n"))
        """
    }

    private static func simplified(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var kept: [CGPoint] = []
        var last: CGPoint?
        for point in points {
            if let previous = last, hypot(point.x - previous.x, point.y - previous.y) < 3 {
                continue
            }
            kept.append(point)
            last = point
        }
        return kept
    }

    private static func sampled(_ points: [CGPoint], maxPoints: Int) -> [CGPoint] {
        guard points.count > maxPoints, maxPoints > 1 else { return points }
        return (0..<maxPoints).map { index in
            let sourceIndex = Int((Double(index) / Double(maxPoints - 1)) * Double(points.count - 1))
            return points[sourceIndex]
        }
    }
}

public struct UserAnnotationToolbarActions {
    public let done: () -> Void
    public let clear: () -> Void
    public let cancel: () -> Void

    public init(done: @escaping () -> Void, clear: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.done = done
        self.clear = clear
        self.cancel = cancel
    }
}

@MainActor
public final class UserAnnotationController {
    private let window: NSWindow
    private let drawView: AnnotationDrawView
    private let toolbar = UserAnnotationToolbarController()
    private var screen: NSScreen?
    private var screenIndex = 0
    private var strokes: [[CGPoint]] = []
    private var currentStroke: [CGPoint] = []

    public init() {
        let frame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        drawView = AnnotationDrawView(frame: CGRect(origin: .zero, size: frame.size))
        window.contentView = drawView
        drawView.onMouseDown = { [weak self] point in self?.beginStroke(at: point) }
        drawView.onMouseDragged = { [weak self] point in self?.extendStroke(to: point) }
        drawView.onMouseUp = { [weak self] point in self?.endStroke(at: point) }
    }

    public func begin(
        on requestedScreen: NSScreen? = nil,
        existing annotation: UserScreenAnnotation? = nil,
        showsToolbar: Bool = false,
        toolbarActions: UserAnnotationToolbarActions? = nil
    ) {
        let mouseRect = CGRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 1))
        let selectedScreen = requestedScreen
            ?? ScreenPerception.screen(containing: mouseRect)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let selectedScreen else { return }
        screen = selectedScreen
        screenIndex = NSScreen.screens.firstIndex { $0 === selectedScreen || $0.frame == selectedScreen.frame } ?? 0
        strokes = annotation?.screenFrame == selectedScreen.frame ? annotation?.strokes ?? [] : []
        currentStroke = []
        let frame = selectedScreen.frame
        window.orderOut(nil)
        window.setFrame(frame, display: false)
        window.ignoresMouseEvents = false
        drawView.frame = CGRect(origin: .zero, size: frame.size)
        drawView.screenOrigin = frame.origin
        drawView.backgroundSampler = AnnotationBackgroundSampler(screen: selectedScreen)
        refreshView()
        window.orderFrontRegardless()
        if showsToolbar, let toolbarActions {
            toolbar.show(on: selectedScreen, actions: toolbarActions)
        } else {
            toolbar.hide()
        }
    }

    public func finish() -> UserScreenAnnotation? {
        commitCurrentStroke()
        window.orderOut(nil)
        toolbar.hide()
        guard let screen, !strokes.isEmpty else { return nil }
        return UserScreenAnnotation(screenIndex: screenIndex, screenFrame: screen.frame, strokes: strokes)
    }

    public func cancel() {
        currentStroke = []
        window.orderOut(nil)
        toolbar.hide()
    }

    public func clear() {
        currentStroke = []
        strokes = []
        refreshView()
    }

    private func beginStroke(at point: CGPoint) {
        currentStroke = [point]
        refreshView()
    }

    private func extendStroke(to point: CGPoint) {
        guard !currentStroke.isEmpty else {
            beginStroke(at: point)
            return
        }
        currentStroke.append(point)
        refreshView()
    }

    private func endStroke(at point: CGPoint) {
        if currentStroke.isEmpty {
            currentStroke = [point]
        } else {
            currentStroke.append(point)
        }
        commitCurrentStroke()
        refreshView()
    }

    private func commitCurrentStroke() {
        let simplified = UserScreenAnnotation(screenIndex: screenIndex, screenFrame: screen?.frame ?? .zero, strokes: [currentStroke]).strokes.first
        if let simplified {
            strokes.append(simplified)
        }
        currentStroke = []
    }

    private func refreshView() {
        let active = currentStroke.count >= 2 ? strokes + [currentStroke] : strokes
        drawView.scene = DrawingScene(marks: active.map { .path(points: $0, shape: .curve) })
        drawView.marks = []
        drawView.needsDisplay = true
    }
}

@MainActor
private final class UserAnnotationToolbarController {
    private final class ToolbarPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private let window: NSPanel
    private let doneButton = RetroButton(title: "Done")
    private let clearButton = RetroButton(title: "Clear")
    private let cancelButton = RetroButton(title: "Cancel")

    init() {
        let size = CGSize(width: 260, height: 38)
        window = ToolbarPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = WindowLevelPolicy.bubbleLevel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = true
        window.backgroundColor = RetroPalette.face
        window.hasShadow = true
        window.hidesOnDeactivate = false

        let panel = RetroPanel(frame: CGRect(origin: .zero, size: size))
        let label = NSTextField(labelWithString: "Annotate")
        label.font = RetroFont.ui(11, bold: true)
        label.textColor = RetroPalette.text
        label.frame = CGRect(x: 10, y: 11, width: 72, height: 16)
        panel.addSubview(label)

        doneButton.frame = CGRect(x: 88, y: 7, width: 50, height: 23)
        clearButton.frame = CGRect(x: 143, y: 7, width: 52, height: 23)
        cancelButton.frame = CGRect(x: 200, y: 7, width: 52, height: 23)
        panel.addSubview(doneButton)
        panel.addSubview(clearButton)
        panel.addSubview(cancelButton)

        window.contentView = panel
    }

    func show(on screen: NSScreen, actions: UserAnnotationToolbarActions) {
        doneButton.onClick = actions.done
        clearButton.onClick = actions.clear
        cancelButton.onClick = actions.cancel

        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 14
        )
        window.setFrame(CGRect(origin: origin, size: size), display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
        doneButton.onClick = nil
        clearButton.onClick = nil
        cancelButton.onClick = nil
    }
}

enum AnnotationBackingTone: Equatable {
    case dark
}

struct AnnotationPalette {
    let primary: NSColor
    let backing: NSColor?
    let inkBacking: NSColor

    init(luminance: CGFloat?, fallbackAppearance: NSAppearance) {
        primary = NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.05, alpha: 1)
        backing = Self.backingTone(luminance: luminance, fallbackAppearance: fallbackAppearance)?.color
        inkBacking = backing ?? NSColor.black.withAlphaComponent(0.72)
    }

    static func backingTone(luminance: CGFloat?, fallbackAppearance: NSAppearance) -> AnnotationBackingTone? {
        if let luminance {
            return luminance > 0.68 ? .dark : nil
        }
        let match = fallbackAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? nil : .dark
    }
}

private extension AnnotationBackingTone {
    var color: NSColor {
        switch self {
        case .dark: return .black
        }
    }
}

final class AnnotationBackgroundSampler {
    private let screenFrame: CGRect
    private let width: Int
    private let height: Int
    private let pixels: [UInt8]

    init?(screen: NSScreen?) {
        guard let screen,
              let displayID = Self.displayID(for: screen),
              let image = CGDisplayCreateImage(displayID) else {
            return nil
        }
        self.screenFrame = screen.frame
        self.width = image.width
        self.height = image.height
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drew = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drew else { return nil }
        self.pixels = buffer
    }

    func averageLuminance(around points: [CGPoint]) -> CGFloat? {
        let samples = points.compactMap(luminance(at:))
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / CGFloat(samples.count)
    }

    private func luminance(at point: CGPoint) -> CGFloat? {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return nil }
        let xRatio = (point.x - screenFrame.minX) / screenFrame.width
        let yRatio = (screenFrame.maxY - point.y) / screenFrame.height
        guard xRatio >= 0, xRatio <= 1, yRatio >= 0, yRatio <= 1 else { return nil }
        let x = min(width - 1, max(0, Int(xRatio * CGFloat(width))))
        let y = min(height - 1, max(0, Int(yRatio * CGFloat(height))))
        let index = (y * width + x) * 4
        guard pixels.indices.contains(index + 2) else { return nil }
        let r = CGFloat(pixels[index]) / 255
        let g = CGFloat(pixels[index + 1]) / 255
        let b = CGFloat(pixels[index + 2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
