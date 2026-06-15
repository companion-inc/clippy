import AppKit

/// Clippy's one and only bubble. It shows exactly one thing at a time:
///   • a single message line (greeting or the latest reply), or
///   • the input field (when you double-click the mascot).
/// While Clippy is thinking, the bubble is hidden entirely — the character's
/// own Thinking animation carries it, like the original assistant. Double-click
/// the mascot to open the input; click away and it disappears. Type face is Microsoft Sans
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
        ClippyBalloonStyle.font(size, bold: bold, theme: theme.balloon)
    }

    public let window: NSPanel
    private let theme: MascotTheme
    private let balloonLayer: CAShapeLayer
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let inputScrollView = NSScrollView()
    private let inputTextView = InputTextView(frame: .zero)
    private let inputPlaceholderLabel: NSTextField

    private var mode: Mode = .message
    private var messageText = ""
    private var onSend: ((String) -> Void)?
    private var anchorFrame: CGRect = .zero
    private var autoHideTimer: Timer?

    public init(theme: MascotTheme = .clippy) {
        self.theme = theme
        self.balloonLayer = ClippyBalloonStyle.makeShapeLayer(theme: theme.balloon)
        self.inputPlaceholderLabel = NSTextField(labelWithString: theme.askPlaceholder)
        self.window = KeyPanel(
            contentRect: CGRect(x: 0, y: 0, width: theme.balloon.minWidth, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let root = NSView(frame: window.frame)
        root.wantsLayer = true
        root.layer?.addSublayer(balloonLayer)

        messageLabel.font = uiFont(12)
        messageLabel.textColor = theme.balloon.textColor
        messageLabel.maximumNumberOfLines = 0
        root.addSubview(messageLabel)

        inputTextView.font = uiFont(13)
        inputTextView.textColor = theme.balloon.textColor
        inputTextView.drawsBackground = false
        inputTextView.isRichText = false
        inputTextView.isAutomaticQuoteSubstitutionEnabled = false
        inputTextView.isAutomaticDashSubstitutionEnabled = false
        inputTextView.isHorizontallyResizable = false
        inputTextView.isVerticallyResizable = true
        inputTextView.textContainerInset = NSSize(width: 0, height: 1)
        inputTextView.textContainer?.lineFragmentPadding = 0
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.delegate = self
        inputTextView.onSubmit = { [weak self] in self?.submitInput() }
        inputTextView.onCancel = { [weak self] in self?.hide() }

        inputScrollView.drawsBackground = false
        inputScrollView.borderType = .noBorder
        inputScrollView.hasVerticalScroller = true
        inputScrollView.autohidesScrollers = true
        inputScrollView.documentView = inputTextView
        inputScrollView.isHidden = true
        root.addSubview(inputScrollView)

        inputPlaceholderLabel.font = uiFont(13)
        inputPlaceholderLabel.textColor = theme.balloon.mutedTextColor
        inputPlaceholderLabel.isHidden = true
        root.addSubview(inputPlaceholderLabel)

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

    public var isVisible: Bool { window.isVisible }
    public var isInputMode: Bool { mode == .input && window.isVisible }

    public func setAnchor(_ frame: CGRect) {
        anchorFrame = frame
        if window.isVisible { positionWindow() }
    }

    public func configure(onSend: @escaping (String) -> Void) {
        self.onSend = onSend
    }

    // MARK: - Single-purpose states

    /// A passive one-line message (greeting, reply). Doesn't steal focus.
    public func showMessage(_ text: String, autoHide: TimeInterval? = nil) {
        messageText = text
        mode = .message
        relayout()
        window.orderFrontRegardless()
        scheduleAutoHide(autoHide)
    }

    /// Double-click the mascot: show only the input, focused. Click-away dismisses it.
    public func openInput() {
        cancelAutoHide()
        mode = .input
        inputTextView.string = ""
        relayout()
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
        messageText = text
        mode = .message
        relayout()
        window.orderFrontRegardless()
    }

    public func hide() {
        cancelAutoHide()
        window.orderOut(nil)
    }

    // MARK: - Layout (one active region; bubble grows to fit)

    private func relayout() {
        let contentWidth = measuredContentWidth()
        let windowWidth = contentWidth + theme.balloon.pad * 2

        messageLabel.isHidden = mode != .message
        inputScrollView.isHidden = mode != .input
        inputPlaceholderLabel.isHidden = mode != .input || !inputTextView.string.isEmpty

        var contentHeight: CGFloat = 0
        switch mode {
        case .input:
            contentHeight = measuredInputHeight(width: contentWidth)
        case .message:
            contentHeight = measuredLabelHeight(messageText.isEmpty ? "…" : messageText, width: contentWidth)
        }

        let windowHeight = theme.balloon.tailHeight + theme.balloon.pad + contentHeight + theme.balloon.pad
        window.setContentSize(CGSize(width: windowWidth, height: windowHeight))
        balloonLayer.frame = CGRect(origin: .zero, size: CGSize(width: windowWidth, height: windowHeight))
        balloonLayer.path = ClippyBalloonStyle.path(
            size: CGSize(width: windowWidth, height: windowHeight),
            theme: theme.balloon
        )

        let contentY = theme.balloon.tailHeight + theme.balloon.pad
        let contentRect = CGRect(x: theme.balloon.pad, y: contentY, width: contentWidth, height: contentHeight)

        switch mode {
        case .input:
            inputScrollView.frame = contentRect
            inputTextView.minSize = NSSize(width: 0, height: contentHeight)
            inputTextView.maxSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
            inputTextView.frame = CGRect(origin: .zero, size: contentRect.size)
            inputTextView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
            inputPlaceholderLabel.frame = CGRect(
                x: contentRect.minX,
                y: contentRect.minY + 1,
                width: contentRect.width,
                height: 18
            )
        case .message:
            messageLabel.frame = contentRect
            messageLabel.stringValue = messageText
        }

        positionWindow()
    }

    private func positionWindow() {
        let size = window.frame.size
        var x = anchorFrame.midX - size.width / 2
        var y = anchorFrame.maxY + 4
        if let visible = NSScreen.main?.visibleFrame {
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
            text = inputTextView.string.isEmpty ? inputPlaceholderLabel.stringValue : inputTextView.string
            fontSize = 13
        case .message:
            text = messageText.isEmpty ? "…" : messageText
            fontSize = 12
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = lines.map { String($0) }.max { $0.count < $1.count } ?? text
        let attributed = NSAttributedString(string: longest, attributes: [.font: uiFont(fontSize)])
        let width = ceil(attributed.size().width) + 4
        return min(
            theme.balloon.maxWidth - theme.balloon.pad * 2,
            max(theme.balloon.minWidth - theme.balloon.pad * 2, width)
        )
    }

    private func measuredLabelHeight(_ text: String, width: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: uiFont(12)])
        let rect = attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height) + 2
    }

    private func measuredInputHeight(width: CGFloat) -> CGFloat {
        let text = inputTextView.string.isEmpty ? inputPlaceholderLabel.stringValue : inputTextView.string
        let attributed = NSAttributedString(string: text, attributes: [.font: uiFont(13)])
        let rect = attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let height = max(theme.balloon.minInputHeight, ceil(rect.height) + 3)
        return min(height, theme.balloon.maxInputHeight)
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
