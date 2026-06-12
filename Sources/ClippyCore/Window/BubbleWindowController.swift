import AppKit

/// The classic Office assistant speech bubble.
/// Faithful to the originals:
/// - Background 00E1FFFF (BGR) = RGB(255, 255, 225), black text, black
///   border: clippit.acd DefineBalloon (Research/sources/repos/Cosmo-Clippy).
/// - 1px border, 5px corner radius, 8px padding, ~200px max text width,
///   tail offset to the side near the character: clippy.js src/clippy.css.
public final class BubbleWindowController {
    private static let balloonColor = NSColor(calibratedRed: 1.0, green: 1.0, blue: 225.0 / 255.0, alpha: 1)
    private static let cornerRadius: CGFloat = 5
    private static let tailSize = CGSize(width: 10, height: 14)
    private static let padding: CGFloat = 8
    private static let maxTextWidth: CGFloat = 200

    public let window: NSWindow
    private let balloonLayer = CAShapeLayer()
    private let label = NSTextField(wrappingLabelWithString: "")
    private var hideTimer: Timer?

    public init() {
        self.window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 180, height: 60),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        let view = NSView(frame: window.contentLayoutRect)
        view.wantsLayer = true

        balloonLayer.fillColor = Self.balloonColor.cgColor
        balloonLayer.strokeColor = NSColor.black.cgColor
        balloonLayer.lineWidth = 1
        view.layer?.addSublayer(balloonLayer)

        label.font = .systemFont(ofSize: 12)
        label.textColor = .black
        view.addSubview(label)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = WindowLevelPolicy.bubbleLevel
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = view
    }

    public func show(
        text: String,
        anchoredTo mascotFrame: CGRect,
        hideAfter delay: TimeInterval? = nil,
        attachedTo parentWindow: NSWindow? = nil
    ) {
        label.stringValue = text

        let textSize = label.sizeThatFits(NSSize(width: Self.maxTextWidth, height: .greatestFiniteMagnitude))
        let balloonSize = CGSize(
            width: max(120, textSize.width + Self.padding * 2),
            height: textSize.height + Self.padding * 2
        )
        let windowSize = CGSize(
            width: balloonSize.width,
            height: balloonSize.height + Self.tailSize.height
        )

        label.frame = CGRect(
            x: Self.padding,
            y: Self.tailSize.height + Self.padding,
            width: balloonSize.width - Self.padding * 2,
            height: textSize.height
        )
        balloonLayer.path = Self.balloonPath(balloonSize: balloonSize)

        // The bubble sits above the character, shifted so the tail points at
        // the head rather than hanging dead center.
        let frame = CGRect(
            x: mascotFrame.midX - balloonSize.width * 0.62,
            y: mascotFrame.maxY + 2,
            width: windowSize.width,
            height: windowSize.height
        )
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        // As a child window, the bubble follows when the character is dragged.
        if let parentWindow, window.parent !== parentWindow {
            window.parent?.removeChildWindow(window)
            parentWindow.addChildWindow(window, ordered: .above)
        }

        hideTimer?.invalidate()
        if let delay {
            hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.hide()
                }
            }
        }
    }

    public func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    /// One continuous outline: rounded rectangle with the tail built into the
    /// bottom edge (offset right, toward the character) so the border never
    /// crosses the tail.
    private static func balloonPath(balloonSize: CGSize) -> CGPath {
        let inset: CGFloat = 0.5
        let left = inset
        let right = balloonSize.width - inset
        let bottom = tailSize.height
        let top = tailSize.height + balloonSize.height - inset
        let r = cornerRadius

        // Tail emerges from the bottom edge, offset toward the right side
        // where the character stands; the tip drops nearly straight down.
        let tailRightX = right - balloonSize.width * 0.28
        let tailLeftX = tailRightX - tailSize.width
        let tipX = tailLeftX + 2

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + r, y: bottom))
        path.addLine(to: CGPoint(x: tailLeftX, y: bottom))
        path.addLine(to: CGPoint(x: tipX, y: inset))
        path.addLine(to: CGPoint(x: tailRightX, y: bottom))
        path.addLine(to: CGPoint(x: right - r, y: bottom))
        path.addArc(
            tangent1End: CGPoint(x: right, y: bottom),
            tangent2End: CGPoint(x: right, y: bottom + r),
            radius: r
        )
        path.addLine(to: CGPoint(x: right, y: top - r))
        path.addArc(
            tangent1End: CGPoint(x: right, y: top),
            tangent2End: CGPoint(x: right - r, y: top),
            radius: r
        )
        path.addLine(to: CGPoint(x: left + r, y: top))
        path.addArc(
            tangent1End: CGPoint(x: left, y: top),
            tangent2End: CGPoint(x: left, y: top - r),
            radius: r
        )
        path.addLine(to: CGPoint(x: left, y: bottom + r))
        path.addArc(
            tangent1End: CGPoint(x: left, y: bottom),
            tangent2End: CGPoint(x: left + r, y: bottom),
            radius: r
        )
        path.closeSubpath()
        return path
    }
}
