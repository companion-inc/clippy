import AppKit
import CoreGraphics

/// A resolved drawing instruction in global screen coordinates (y-up).
public enum AnnotationMark: Equatable, Sendable {
    case ring(center: CGPoint, radius: CGFloat, kind: RingKind)
    case region(center: CGPoint, radius: CGFloat)
    case path(points: [CGPoint], shape: GroundingTag.ShapeKind)

    public enum RingKind: Equatable, Sendable { case target, hover }

    /// Build a mark from a grounding tag whose coordinates are already in screen space.
    /// `POINT` produces no mark — Clippy's own body is the pointer.
    public init?(tag: GroundingTag) {
        switch tag {
        case let .target(p, r, _, _): self = .ring(center: p, radius: CGFloat(r), kind: .target)
        case let .hover(p, r, _, _): self = .ring(center: p, radius: CGFloat(r), kind: .hover)
        case let .highlight(p, r, _, _): self = .region(center: p, radius: CGFloat(r))
        case let .shape(kind, pts, _, _): self = .path(points: pts, shape: kind)
        case .point, .act: return nil   // body-only directives draw no on-screen mark
        }
    }
}

/// Borderless, transparent, click-through overlay that draws Clippy's on-screen marks
/// (target/hover rings, highlight outlines, shape paths) in global screen coordinates.
/// Clippy's body is the visible pointer; this overlay is only for marks that need ink.
@MainActor
public final class AnnotationOverlayWindow {
    private let window: NSWindow
    private let drawView: AnnotationDrawView

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
        let frame = (screen ?? NSScreen.main)?.frame ?? window.frame
        window.orderOut(nil)
        window.setFrame(frame, display: false)
        drawView.frame = CGRect(origin: .zero, size: frame.size)
        drawView.screenOrigin = frame.origin
        drawView.backgroundSampler = marks.isEmpty ? nil : AnnotationBackgroundSampler(screen: screen ?? NSScreen.main)
        drawView.marks = marks
        drawView.needsDisplay = true
        if marks.isEmpty {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    public func clear() {
        show([])
    }
}

@MainActor
final class AnnotationDrawView: NSView {
    var marks: [AnnotationMark] = []
    var screenOrigin: CGPoint = .zero
    var backgroundSampler: AnnotationBackgroundSampler?
    private let markScale: CGFloat = 1

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for mark in marks {
            switch mark {
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
                    let r: CGFloat = 32 * markScale
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
        if let backing = palette.backing {
            drawPathStroke(ctx, points: points, shape: shape, color: backing, width: 7 * markScale)
            drawPathStroke(ctx, points: points, shape: shape, color: palette.primary, width: 3 * markScale)
        } else {
            drawPathStroke(ctx, points: points, shape: shape, color: palette.primary, width: 4 * markScale)
        }
    }

    private func drawLine(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, palette: AnnotationPalette) {
        if let backing = palette.backing {
            drawPathStroke(ctx, points: [a, b], shape: .line, color: backing, width: 6 * markScale)
            drawPathStroke(ctx, points: [a, b], shape: .line, color: palette.primary, width: 3 * markScale)
        } else {
            drawPathStroke(ctx, points: [a, b], shape: .line, color: palette.primary, width: 4 * markScale)
        }
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
}

enum AnnotationBackingTone: Equatable {
    case dark
}

struct AnnotationPalette {
    let primary: NSColor
    let backing: NSColor?

    init(luminance: CGFloat?, fallbackAppearance: NSAppearance) {
        primary = ClippyBalloonSpec.current.fillColor
        backing = Self.backingTone(luminance: luminance, fallbackAppearance: fallbackAppearance)?.color
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
