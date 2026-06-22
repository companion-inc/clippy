import AppKit

public final class SidekickHitView: NSView, NSDraggingSource {
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

    /// When set, dragging the character carries this .app bundle instead of moving
    /// the character. Used for macOS Privacy permission lists.
    public var permissionDragAppURL: URL? {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    private let visibleHitTest: (NSPoint) -> Bool
    private var mouseDownScreenLocation: NSPoint?
    private var mouseDownWindowOrigin: NSPoint?
    private var didDrag = false
    private var didStartPermissionDrag = false
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
        guard (dx * dx + dy * dy) >= 16 else { return }
        didDrag = true
        if let permissionDragAppURL {
            guard didStartPermissionDrag == false else { return }
            didStartPermissionDrag = true
            beginPermissionDrag(appURL: permissionDragAppURL, event: event)
        } else {
            window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let hadMouseDown = mouseDownScreenLocation != nil
        defer {
            mouseDownScreenLocation = nil
            mouseDownWindowOrigin = nil
            didDrag = false
            didStartPermissionDrag = false
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

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: permissionDragAppURL == nil ? .arrow : .openHand)
    }

    public func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    public func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        NSCursor.arrow.set()
    }

    private func beginPermissionDrag(appURL: URL, event: NSEvent) {
        NSCursor.closedHand.set()
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let dragImage = permissionDragImage(appURL: appURL)
        let size = dragImage.size
        item.setDraggingFrame(
            CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height),
            contents: dragImage
        )
        beginDraggingSession(with: [item], event: event, source: self)
    }

    private func permissionDragImage(appURL: URL) -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        image.size = bounds.size
        return image
    }
}
