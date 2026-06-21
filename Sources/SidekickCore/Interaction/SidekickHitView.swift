import AppKit

public final class SidekickHitView: NSView {
    /// Supplies the context menu shown on right-click, like the original
    /// assistant's Animate!/Options menu.
    public var menuProvider: (() -> NSMenu?)?

    /// Custom right-click presenter. Used by the app for its period-styled menu.
    public var rightClickHandler: ((NSEvent, NSView) -> Void)?

    /// Invoked on an intentional character click — opens the Sidekick input.
    public var onClick: (() -> Void)?

    /// Invoked on an intentional character double-click — opens contextual help.
    public var onDoubleClick: (() -> Void)?

    /// Invoked when the focused character window receives typed input.
    public var onKeyDown: ((NSEvent) -> Bool)?

    private let visibleHitTest: (NSPoint) -> Bool
    private var mouseDownScreenLocation: NSPoint?
    private var mouseDownWindowOrigin: NSPoint?
    private var didDrag = false
    private var pendingSingleClick: DispatchWorkItem?

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

    deinit {
        pendingSingleClick?.cancel()
    }

    public override var isFlipped: Bool {
        false
    }

    public override var acceptsFirstResponder: Bool {
        true
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) && visibleHitTest(point) ? self : nil
    }

    public override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let rightClickHandler {
            rightClickHandler(event, self)
            return
        }
        guard let menu = menuProvider?() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
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
            return
        }
        if event.clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            onDoubleClick?()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSingleClick = nil
            self?.onClick?()
        }
        pendingSingleClick?.cancel()
        pendingSingleClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }
}
