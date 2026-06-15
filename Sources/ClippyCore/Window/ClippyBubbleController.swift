import AppKit

/// Clippy's one and only bubble. It shows exactly one thing at a time:
///   • a single message line (greeting or the latest reply), or
///   • the input field (when you double-click Clippy).
/// While Clippy is thinking, the bubble is hidden entirely — the character's
/// own Thinking animation carries it, like the original assistant. Double-click
/// Clippy to open the input; click away and it disappears. Type face is Microsoft Sans
/// Serif (the modern name for the MS Sans Serif the original balloon used).
public final class ClippyBubbleController: NSObject, NSTextViewDelegate, NSWindowDelegate {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class InputTextView: NSTextView {
        var onSubmit: (() -> Void)?
        var onCancel: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36 where !event.modifierFlags.contains(.shift),
                 76 where !event.modifierFlags.contains(.shift):
                onSubmit?()
            case 53:
                onCancel?()
            default:
                super.keyDown(with: event)
            }
        }
    }

    private enum Mode { case message, input }

    private func uiFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
        ClippyBalloonStyle.font(size, bold: bold, spec: spec.balloon)
    }

    public let window: NSPanel
    private let spec: ClippySpec
    private let balloonLayer: CAShapeLayer
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let inputScrollView = NSScrollView()
    private let inputTextView = InputTextView(frame: .zero)
    private let inputPlaceholderView = NSTextView(frame: .zero)

    private var mode: Mode = .message
    private var messageText = ""
    private var onSend: ((String) -> Void)?
    private var anchorFrame: CGRect = .zero
    private weak var anchorWindow: NSWindow?
    private var autoHideTimer: Timer?

    public init(spec: ClippySpec = .current) {
        self.spec = spec
        self.balloonLayer = ClippyBalloonStyle.makeShapeLayer(spec: spec.balloon)
        self.window = KeyPanel(
            contentRect: CGRect(x: 0, y: 0, width: spec.balloon.minWidth, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let root = NSView(frame: window.frame)
        root.wantsLayer = true
        root.layer?.addSublayer(balloonLayer)

        messageLabel.font = uiFont(spec.balloon.messageFontSize)
        messageLabel.textColor = spec.balloon.textColor
        messageLabel.maximumNumberOfLines = 0
        root.addSubview(messageLabel)

        configureInputTextView(inputTextView, textColor: spec.balloon.textColor)
        inputTextView.delegate = self
        inputTextView.onSubmit = { [weak self] in self?.submitInput() }
        inputTextView.onCancel = { [weak self] in self?.hide() }

        configureInputTextView(inputPlaceholderView, textColor: spec.balloon.mutedTextColor)
        inputPlaceholderView.string = spec.askPlaceholder
        inputPlaceholderView.isEditable = false
        inputPlaceholderView.isSelectable = false
        inputPlaceholderView.isHidden = true
        root.addSubview(inputPlaceholderView)

        inputScrollView.drawsBackground = false
        inputScrollView.borderType = .noBorder
        inputScrollView.hasVerticalScroller = true
        inputScrollView.autohidesScrollers = true
        inputScrollView.documentView = inputTextView
        inputScrollView.isHidden = true
        root.addSubview(inputScrollView)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = WindowLevelPolicy.bubbleLevel
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.contentView = root
    }

    private func configureInputTextView(_ textView: NSTextView, textColor: NSColor) {
        textView.font = uiFont(spec.balloon.inputFontSize)
        textView.textColor = textColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
    }

    public var isVisible: Bool { window.isVisible }
    public var isInputMode: Bool { mode == .input && window.isVisible }

    public func setAnchor(_ frame: CGRect, repositionVisible: Bool = true) {
        anchorFrame = frame
        if repositionVisible, window.isVisible {
            positionWindow()
        }
    }

    public func setAnchorWindow(_ window: NSWindow?) {
        if let parent = self.window.parent, parent !== window {
            parent.removeChildWindow(self.window)
        }
        anchorWindow = window
        if self.window.isVisible { attachToAnchorWindow() }
    }

    private func attachToAnchorWindow() {
        guard let anchorWindow else {
            return
        }
        if let parent = window.parent, parent !== anchorWindow {
            parent.removeChildWindow(window)
        }
        if window.parent !== anchorWindow {
            anchorWindow.addChildWindow(window, ordered: .above)
        }
    }

    public func configure(onSend: @escaping (String) -> Void) {
        self.onSend = onSend
    }

    // MARK: - Single-purpose states

    /// A passive one-line message (greeting, reply). Doesn't steal focus.
    public func showMessage(_ text: String, autoHide: TimeInterval? = nil) {
        stopThinking()
        messageText = text
        mode = .message
        relayout()
        attachToAnchorWindow()
        window.orderFrontRegardless()
        scheduleAutoHide(autoHide)
    }

    /// Double-click Clippy: show only the input, focused. Click-away dismisses it.
    public func openInput() {
        stopThinking()
        cancelAutoHide()
        mode = .input
        inputTextView.string = ""
        relayout()
        attachToAnchorWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(inputTextView)
    }

    public func toggleInput() {
        if mode == .input && window.isVisible { hide() } else { openInput() }
    }

    /// The character's Thinking animation represents the thinking state.
    public func recordUserLine(_ _: String) {
        cancelAutoHide()
    }

    /// Reply arrived — show just the reply.
    public func showReply(_ text: String) {
        stopThinking()
        messageText = text
        mode = .message
        relayout()
        attachToAnchorWindow()
        window.orderFrontRegardless()
    }

    public func hide() {
        stopThinking()
        cancelAutoHide()
        if let anchorWindow, window.parent === anchorWindow {
            anchorWindow.removeChildWindow(window)
        }
        window.orderOut(nil)
    }

    // MARK: - Thinking indicator

    private var thinkingTimer: Timer?
    private var thinkingStep = 0
    private let thinkingFrames = ["•", "•  •", "•  •  •"]

    /// Animated dots bubble while Clippy is thinking — shown alongside the
    /// character's head-scratch animation so there's a visible "working" cue.
    public func showThinking() {
        cancelAutoHide()
        thinkingStep = 0
        renderThinkingFrame()
        attachToAnchorWindow()
        window.orderFrontRegardless()
        thinkingTimer?.invalidate()
        thinkingTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.renderThinkingFrame()
        }
    }

    private func renderThinkingFrame() {
        messageText = thinkingFrames[thinkingStep % thinkingFrames.count]
        mode = .message
        relayout()
        thinkingStep += 1
    }

    private func stopThinking() {
        thinkingTimer?.invalidate()
        thinkingTimer = nil
    }

    // MARK: - Layout (one active region; bubble grows to fit)

    private func relayout() {
        let contentWidth = measuredContentWidth()
        let shapeWidth = contentWidth + spec.balloon.pad * 2

        messageLabel.isHidden = mode != .message
        inputScrollView.isHidden = mode != .input
        inputPlaceholderView.isHidden = mode != .input || !inputTextView.string.isEmpty

        var contentHeight: CGFloat = 0
        switch mode {
        case .input:
            contentHeight = measuredInputHeight(width: contentWidth)
        case .message:
            contentHeight = measuredLabelHeight(messageText.isEmpty ? "…" : messageText, width: contentWidth)
        }

        let shapeHeight = spec.balloon.tailHeight + spec.balloon.pad + contentHeight + spec.balloon.pad
        let windowWidth = shapeWidth
        let windowHeight = shapeHeight
        let shapeOrigin = CGPoint.zero
        let shapeSize = CGSize(width: shapeWidth, height: shapeHeight)
        window.setContentSize(CGSize(width: windowWidth, height: windowHeight))
        balloonLayer.frame = CGRect(origin: shapeOrigin, size: shapeSize)
        balloonLayer.path = ClippyBalloonStyle.path(size: shapeSize, spec: spec.balloon)

        let contentY = shapeOrigin.y + spec.balloon.tailHeight + spec.balloon.pad
        let contentRect = CGRect(
            x: shapeOrigin.x + spec.balloon.pad,
            y: contentY,
            width: contentWidth,
            height: contentHeight
        )

        switch mode {
        case .input:
            inputPlaceholderView.frame = contentRect
            inputPlaceholderView.minSize = NSSize(width: 0, height: contentHeight)
            inputPlaceholderView.maxSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
            inputPlaceholderView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
            inputScrollView.frame = contentRect
            inputTextView.minSize = NSSize(width: 0, height: contentHeight)
            inputTextView.maxSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
            inputTextView.frame = CGRect(origin: .zero, size: contentRect.size)
            inputTextView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        case .message:
            messageLabel.frame = contentRect
            messageLabel.stringValue = messageText
        }

        positionWindow()
    }

    private func positionWindow() {
        let parentBeforePositioning = window.parent
        parentBeforePositioning?.removeChildWindow(window)
        defer {
            if window.isVisible {
                attachToAnchorWindow()
            }
        }

        let size = window.frame.size
        let shapeOriginX: CGFloat = 0
        let shapeOriginY: CGFloat = 0
        let shapeWidth = size.width
        let tailTipX = shapeOriginX + shapeWidth / 2 + spec.balloon.tailTipOffset
        let tailTipY = shapeOriginY + 0.5
        var x = anchorFrame.midX - tailTipX
        var y = anchorFrame.maxY + 4 - tailTipY
        let anchorCenter = CGPoint(x: anchorFrame.midX, y: anchorFrame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchorCenter) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
            if y + size.height > visible.maxY { y = visible.maxY - size.height - 8 }
            y = max(y, visible.minY + 8)
        }
        window.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func measuredContentWidth() -> CGFloat {
        let text: String
        let fontSize: CGFloat
        switch mode {
        case .input:
            text = inputTextView.string.isEmpty ? inputPlaceholderView.string : inputTextView.string
            fontSize = spec.balloon.inputFontSize
        case .message:
            text = messageText.isEmpty ? "…" : messageText
            fontSize = spec.balloon.messageFontSize
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = lines.map { String($0) }.max { $0.count < $1.count } ?? text
        let attributed = NSAttributedString(string: longest, attributes: [.font: uiFont(fontSize)])
        let width = ceil(attributed.size().width) + 4
        return min(
            spec.balloon.maxWidth - spec.balloon.pad * 2,
            max(spec.balloon.minWidth - spec.balloon.pad * 2, width)
        )
    }

    private func measuredLabelHeight(_ text: String, width: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: uiFont(spec.balloon.messageFontSize)])
        let rect = attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height) + 2
    }

    private func measuredInputHeight(width: CGFloat) -> CGFloat {
        let text = inputTextView.string.isEmpty ? inputPlaceholderView.string : inputTextView.string
        let attributed = NSAttributedString(string: text, attributes: [.font: uiFont(spec.balloon.inputFontSize)])
        let rect = attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let height = max(spec.balloon.minInputHeight, ceil(rect.height) + 3)
        return min(height, spec.balloon.maxInputHeight)
    }

    private func scheduleAutoHide(_ delay: TimeInterval?) {
        cancelAutoHide()
        guard let delay else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    // MARK: - Click-away dismissal

    public func windowDidResignKey(_ notification: Notification) {
        if mode == .input { hide() }
    }

    public func textDidChange(_ notification: Notification) {
        if mode == .input {
            relayout()
            inputTextView.scrollRangeToVisible(NSRange(location: inputTextView.string.count, length: 0))
        }
    }

    private func submitInput() {
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        inputTextView.string = ""
        relayout()
        if !text.isEmpty { onSend?(text) }
    }

}
