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
/// Replaces Clippy's synthetic cursor overlay — here Clippy's body does the pointing.
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
        window.setFrame(frame, display: false)
        drawView.frame = CGRect(origin: .zero, size: frame.size)
        drawView.screenOrigin = frame.origin
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

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for mark in marks {
            switch mark {
            case let .ring(center, radius, kind):
                let c = local(center)
                let color = (kind == .target ? NSColor.systemBlue : NSColor.systemTeal).cgColor
                ctx.setStrokeColor(color)
                ctx.setLineWidth(4)
                ctx.strokeEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
            case let .region(center, radius):
                let c = local(center)
                ctx.setStrokeColor(NSColor.systemYellow.cgColor)
                ctx.setLineWidth(3)
                let rect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil))
                ctx.strokePath()
            case let .path(points, shape):
                let pts = points.map(local)
                guard let first = pts.first else { break }
                ctx.setStrokeColor(NSColor.systemTeal.cgColor)
                ctx.setLineWidth(4)
                if shape == .circle {
                    let r: CGFloat = 32
                    ctx.strokeEllipse(in: CGRect(x: first.x - r, y: first.y - r, width: r * 2, height: r * 2))
                    break
                }
                ctx.beginPath()
                ctx.move(to: first)
                for p in pts.dropFirst() { ctx.addLine(to: p) }
                ctx.strokePath()
                if shape == .arrow, pts.count >= 2 {
                    drawArrowHead(ctx, from: pts[pts.count - 2], to: pts[pts.count - 1])
                }
            }
        }
    }

    private func drawArrowHead(_ ctx: CGContext, from a: CGPoint, to b: CGPoint) {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let len: CGFloat = 16
        let spread = CGFloat.pi / 7
        ctx.beginPath()
        ctx.move(to: CGPoint(x: b.x - len * cos(angle - spread), y: b.y - len * sin(angle - spread)))
        ctx.addLine(to: b)
        ctx.addLine(to: CGPoint(x: b.x - len * cos(angle + spread), y: b.y - len * sin(angle + spread)))
        ctx.strokePath()
    }

    private func local(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - screenOrigin.x, y: p.y - screenOrigin.y)
    }
}
