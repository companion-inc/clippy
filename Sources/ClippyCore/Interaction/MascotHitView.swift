import AppKit

public final class MascotHitView: NSView {
    /// Supplies the context menu shown on right-click, like the original
    /// assistant's Animate!/Options menu.
    public var menuProvider: (() -> NSMenu?)?

    /// Invoked on a left-click that isn't a drag — opens the ask-Clippy input.
    public var onClick: (() -> Void)?

    private let visibleHitTest: (NSPoint) -> Bool
    private var mouseDownLocation: NSPoint?

    public init(frame: NSRect, visibleHitTest: @escaping (NSPoint) -> Bool) {
        self.visibleHitTest = visibleHitTest
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public override var isFlipped: Bool {
        false
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        visibleHitTest(point) ? self : nil
    }

    public override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    public override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
    }

    public override func mouseUp(with event: NSEvent) {
        // Treat a press-release that didn't travel far as a click, so dragging
        // the character (window-background drag) doesn't also open the input.
        if let start = mouseDownLocation {
            let end = event.locationInWindow
            let dx = end.x - start.x
            let dy = end.y - start.y
            if (dx * dx + dy * dy) < 36 {
                onClick?()
            }
        }
        mouseDownLocation = nil
    }
}
