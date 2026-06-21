import AppKit
import QuartzCore

public final class SidekickWindowController {
    private final class KeyboardWindow: NSWindow {
        var onKeyDown: ((NSEvent) -> Bool)?

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }

        override func keyDown(with event: NSEvent) {
            if onKeyDown?(event) == true {
                return
            }
            super.keyDown(with: event)
        }
    }

    private final class FrameObserver: NSObject, NSWindowDelegate {
        var onFrameChanged: (() -> Void)?

        func windowDidMove(_ notification: Notification) {
            onFrameChanged?()
        }

        func windowDidResize(_ notification: Notification) {
            onFrameChanged?()
        }
    }

    public let window: NSWindow
    private let contentView: SidekickHitView
    private let frameObserver = FrameObserver()

    public var frame: CGRect {
        window.frame
    }

    /// Fired whenever AppKit reports Sidekick's window frame has changed.
    public var onFrameChanged: ((CGRect) -> Void)?

    /// Context menu for right-clicking the character.
    public var contextMenuProvider: (() -> NSMenu?)? {
        get { contentView.menuProvider }
        set { contentView.menuProvider = newValue }
    }

    /// Custom right-click presenter for the character.
    public var rightClickHandler: ((NSEvent, NSView) -> Void)? {
        get { contentView.rightClickHandler }
        set { contentView.rightClickHandler = newValue }
    }

    /// Fired on an intentional character activation gesture.
    public var onCharacterClick: (() -> Void)? {
        get { contentView.onClick }
        set { contentView.onClick = newValue }
    }

    /// Fired on an intentional character double-click gesture.
    public var onCharacterDoubleClick: (() -> Void)? {
        get { contentView.onDoubleClick }
        set { contentView.onDoubleClick = newValue }
    }

    /// Fired when the focused character window receives keyboard input.
    public var onKeyDown: ((NSEvent) -> Bool)? {
        get { contentView.onKeyDown }
        set {
            contentView.onKeyDown = newValue
            (window as? KeyboardWindow)?.onKeyDown = newValue
        }
    }

    public init(
        rendererLayer: CALayer,
        size: CGSize = CGSize(width: 160, height: 160),
        visibleHitTest: @escaping (NSPoint) -> Bool
    ) {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = CGPoint(x: screen.midX - size.width / 2, y: screen.minY + 40)
        self.window = KeyboardWindow(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.contentView = SidekickHitView(frame: CGRect(origin: .zero, size: size), visibleHitTest: visibleHitTest)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = WindowLevelPolicy.sidekickLevel
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        contentView.layer?.addSublayer(rendererLayer)
        window.contentView = contentView
        bindFrameObserver()
    }

    public init(
        rendererView: NSView,
        size: CGSize = CGSize(width: 160, height: 160),
        visibleHitTest: @escaping (NSPoint) -> Bool
    ) {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = CGPoint(x: screen.midX - size.width / 2, y: screen.minY + 40)
        self.window = KeyboardWindow(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.contentView = SidekickHitView(frame: CGRect(origin: .zero, size: size), visibleHitTest: visibleHitTest)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = WindowLevelPolicy.sidekickLevel
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        rendererView.frame = contentView.bounds
        rendererView.autoresizingMask = [.width, .height]
        contentView.addSubview(rendererView)
        window.contentView = contentView
        bindFrameObserver()
    }

    public func show() {
        window.orderFrontRegardless()
    }

    public func hide() {
        window.orderOut(nil)
    }

    public func resize(to size: CGSize, anchoredAt origin: CGPoint, animated: Bool, completion: (() -> Void)? = nil) {
        let frame = CGRect(origin: origin, size: size)
        let finish = { [weak self] in
            guard let self else {
                completion?()
                return
            }
            self.contentView.frame = CGRect(origin: .zero, size: size)
            self.onFrameChanged?(self.window.frame)
            completion?()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            } completionHandler: {
                finish()
            }
        } else {
            window.setFrame(frame, display: true)
            finish()
        }
    }

    public func move(to origin: CGPoint, animated: Bool, completion: (() -> Void)? = nil) {
        let frame = CGRect(origin: origin, size: window.frame.size)
        let finish = { [weak self] in
            guard let self else {
                completion?()
                return
            }
            self.onFrameChanged?(self.window.frame)
            completion?()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            } completionHandler: {
                finish()
            }
        } else {
            window.setFrame(frame, display: true)
            finish()
        }
    }

    private func bindFrameObserver() {
        frameObserver.onFrameChanged = { [weak self] in
            guard let self else { return }
            self.onFrameChanged?(self.window.frame)
        }
        window.delegate = frameObserver
    }
}
