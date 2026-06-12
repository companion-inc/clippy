import AppKit

public final class MascotHitView: NSView {
    /// Supplies the context menu shown on right-click, like the original
    /// assistant's Animate!/Options menu.
    public var menuProvider: (() -> NSMenu?)?

    /// Invoked on an intentional double-click — opens the Sidekick input.
    public var onClick: (() -> Void)?

    private let visibleHitTest: (NSPoint) -> Bool
    private var mouseDownScreenLocation: NSPoint?
    private var mouseDownWindowOrigin: NSPoint?
    private var lastClickScreenLocation: NSPoint?
    private var lastClickTimestamp: TimeInterval?
    private var didDrag = false

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
        mouseDownScreenLocation = NSEvent.mouseLocation
        mouseDownWindowOrigin = window?.frame.origin
        didDrag = false
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let startLocation = mouseDownScreenLocation, let startOrigin = mouseDownWindowOrigin else {
            return
        }
        let currentLocation = NSEvent.mouseLocation
        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y
        if (dx * dx + dy * dy) >= 16 {
            didDrag = true
        }
        window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    public override func mouseUp(with event: NSEvent) {
        let hadMouseDown = mouseDownScreenLocation != nil
        defer {
            mouseDownScreenLocation = nil
            mouseDownWindowOrigin = nil
            didDrag = false
        }
        guard hadMouseDown, !didDrag else {
            lastClickScreenLocation = nil
            lastClickTimestamp = nil
            return
        }

        if event.clickCount >= 2 {
            lastClickScreenLocation = nil
            lastClickTimestamp = nil
            onClick?()
            return
        }

        let clickLocation = NSEvent.mouseLocation
        if
            let previousLocation = lastClickScreenLocation,
            let previousTimestamp = lastClickTimestamp,
            event.timestamp - previousTimestamp <= 0.45
        {
            let dx = clickLocation.x - previousLocation.x
            let dy = clickLocation.y - previousLocation.y
            if (dx * dx + dy * dy) <= 16 {
                lastClickScreenLocation = nil
                lastClickTimestamp = nil
                onClick?()
                return
            }
        }

        lastClickScreenLocation = clickLocation
        lastClickTimestamp = event.timestamp
    }
}
