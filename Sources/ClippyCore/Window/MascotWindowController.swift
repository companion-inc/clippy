import AppKit
import QuartzCore

public final class MascotWindowController {
    public let window: NSWindow
    private let contentView: MascotHitView

    public var frame: CGRect {
        window.frame
    }

    public init(
        rendererLayer: CALayer,
        size: CGSize = CGSize(width: 160, height: 160),
        visibleHitTest: @escaping (NSPoint) -> Bool
    ) {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = CGPoint(x: screen.midX - size.width / 2, y: screen.minY + 40)
        self.window = NSWindow(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.contentView = MascotHitView(frame: CGRect(origin: .zero, size: size), visibleHitTest: visibleHitTest)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = WindowLevelPolicy.mascotLevel
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        contentView.layer?.addSublayer(rendererLayer)
        window.contentView = contentView
    }

    public init(
        rendererView: NSView,
        size: CGSize = CGSize(width: 160, height: 160),
        visibleHitTest: @escaping (NSPoint) -> Bool
    ) {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = CGPoint(x: screen.midX - size.width / 2, y: screen.minY + 40)
        self.window = NSWindow(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.contentView = MascotHitView(frame: CGRect(origin: .zero, size: size), visibleHitTest: visibleHitTest)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = WindowLevelPolicy.mascotLevel
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        rendererView.frame = contentView.bounds
        rendererView.autoresizingMask = [.width, .height]
        contentView.addSubview(rendererView)
        window.contentView = contentView
    }

    public func show() {
        window.orderFrontRegardless()
    }

    public func hide() {
        window.orderOut(nil)
    }
}
