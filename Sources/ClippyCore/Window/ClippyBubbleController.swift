import AppKit

/// Clippy's one and only bubble. It shows exactly one thing at a time:
///   • a single message line (greeting or the latest reply), or
///   • the input field (when you double-click Clippy).
/// While Clippy is thinking, the bubble shows the current backend phase instead
/// of leaving the user with anonymous dots. Double-click Clippy to open the input;
/// click away and it disappears. Type face is Microsoft Sans Serif (the modern
/// name for the MS Sans Serif the original balloon used).
public final class ClippyBubbleController: NSObject, NSTextViewDelegate, NSWindowDelegate {
    public struct Choice {
        public let title: String
        public let action: () -> Void

        public init(title: String, action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }
    }

    private final class KeyPanel: NSPanel {
        var onKeyDown: ((NSEvent) -> Bool)?

        override var canBecomeKey: Bool { true }

        override func keyDown(with event: NSEvent) {
            if onKeyDown?(event) == true {
                return
            }
            super.keyDown(with: event)
        }
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

    private final class BalloonChoiceButton: NSView {
        var title: String { didSet { needsDisplay = true } }
        var onClick: (() -> Void)?
        var isKeyboardFocused = false { didSet { needsDisplay = true } }
        private var pressed = false

        override var isFlipped: Bool { true }

        init(title: String) {
            self.title = title
            super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 18))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func draw(_ dirtyRect: NSRect) {
            let offset = pressed ? CGFloat(1) : 0
            let bulletRect = NSRect(x: 2 + offset, y: 4 + offset, width: 8, height: 8)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: bulletRect).fill()
            NSColor.black.setStroke()
            let outline = NSBezierPath(ovalIn: bulletRect)
            outline.lineWidth = 1
            outline.stroke()
            NSColor(srgbRed: 0.0, green: 0.12, blue: 0.72, alpha: 1).setFill()
            NSBezierPath(ovalIn: bulletRect.insetBy(dx: 2, dy: 2)).fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: RetroFont.ui(11),
                .foregroundColor: RetroPalette.text,
                .paragraphStyle: paragraph,
            ]
            let label = title as NSString
            let textSize = label.size(withAttributes: attrs)
            let textRect = NSRect(
                x: 16 + offset,
                y: max(0, (bounds.height - textSize.height) / 2) + offset,
                width: bounds.width - 16,
                height: textSize.height
            )
            label.draw(in: textRect, withAttributes: attrs)

            if isKeyboardFocused {
                RetroPalette.frame.setStroke()
                let focus = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 1.5))
                let dash: [CGFloat] = [1, 2]
                dash.withUnsafeBufferPointer { buffer in
                    focus.setLineDash(buffer.baseAddress, count: buffer.count, phase: 0)
                }
                focus.lineWidth = 1
                focus.stroke()
            }
        }

        override func mouseDown(with event: NSEvent) {
            pressed = true
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            if inside != pressed {
                pressed = inside
                needsDisplay = true
            }
        }

        override func mouseUp(with event: NSEvent) {
            let fire = pressed && bounds.contains(convert(event.locationInWindow, from: nil))
            pressed = false
            needsDisplay = true
            if fire { onClick?() }
        }
    }

    private enum Mode { case message, input, choices }

    private func uiFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
        ClippyBalloonStyle.font(size, bold: bold, spec: spec.balloon)
    }

    public let window: NSPanel
    private let spec: ClippySpec
    private let root = NSView()
    private let balloonLayer: CAShapeLayer
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let inputScrollView = NSScrollView()
    private let inputTextView = InputTextView(frame: .zero)
    private let inputPlaceholderView = NSTextView(frame: .zero)
    private var choiceButtons: [BalloonChoiceButton] = []
    private var selectedChoiceIndex: Int?

    private var mode: Mode = .message
    private var messageText = ""
    private var onSend: ((String) -> Void)?
    private var anchorFrame: CGRect = .zero
    private weak var anchorWindow: NSWindow?
    private var autoHideTimer: Timer?
    private var typingTimer: Timer?

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

        (window as? KeyPanel)?.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }

        root.frame = window.frame
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
        stopTyping()
        stopThinking()
        clearChoices()
        messageText = text
        mode = .message
        relayout()
        attachToAnchorWindow()
        window.orderFrontRegardless()
        scheduleAutoHide(autoHide)
    }

    public func showMessageForReading(_ text: String) {
        showMessage(text, autoHide: Self.readingAutoHideDelay(for: text))
    }

    /// Double-click Clippy: show only the input, focused. Click-away dismisses it.
    public func openInput() {
        stopTyping()
        stopThinking()
        cancelAutoHide()
        clearChoices()
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
    public func showReply(_ text: String, autoHide: TimeInterval? = nil) {
        stopTyping()
        stopThinking()
        clearChoices()
        messageText = text
        mode = .message
        relayout()
        attachToAnchorWindow()
        window.orderFrontRegardless()
        scheduleAutoHide(autoHide)
    }

    public func showReplyForReading(_ text: String) {
        showReply(text, autoHide: Self.readingAutoHideDelay(for: text))
    }

    public func showStatus(_ text: String) {
        showReply(text)
    }

    public func showChoices(_ prompt: String, choices: [Choice]) {
        stopTyping()
        stopThinking()
        cancelAutoHide()
        clearChoices()
        messageText = prompt
        mode = .choices
        choiceButtons = choices.map { choice in
            let button = BalloonChoiceButton(title: choice.title)
            button.onClick = choice.action
            root.addSubview(button)
            return button
        }
        selectedChoiceIndex = choices.isEmpty ? nil : 0
        relayout()
        attachToAnchorWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func showChoicesTyping(_ prompt: String, choices: [Choice]) {
        stopTyping()
        stopThinking()
        cancelAutoHide()
        clearChoices()
        messageText = ""
        mode = .message
        relayout()
        attachToAnchorWindow()
        window.orderFrontRegardless()

        var index = prompt.startIndex
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.012, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if index == prompt.endIndex {
                timer.invalidate()
                self.typingTimer = nil
                self.showChoices(prompt, choices: choices)
                return
            }
            let nextIndex = prompt.index(after: index)
            self.messageText = String(prompt[..<nextIndex])
            self.mode = .message
            self.relayout()
            index = nextIndex
        }
    }

    public func hide() {
        stopTyping()
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
    private var thinkingStatus = "Thinking"
    private let thinkingSuffixes = ["", ".", "..", "..."]

    /// Animated status bubble while Clippy is thinking — shown alongside the
    /// character's head-scratch animation so there is a visible working cue.
    public func showThinking(_ status: String = "Thinking") {
        cancelAutoHide()
        thinkingStep = 0
        thinkingStatus = status
        renderThinkingFrame()
        attachToAnchorWindow()
        window.orderFrontRegardless()
        thinkingTimer?.invalidate()
        thinkingTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.renderThinkingFrame()
        }
    }

    public func updateThinking(_ status: String) {
        guard thinkingTimer != nil else {
            showThinking(status)
            return
        }
        thinkingStatus = status
        renderThinkingFrame()
    }

    private func renderThinkingFrame() {
        messageText = thinkingStatus + thinkingSuffixes[thinkingStep % thinkingSuffixes.count]
        mode = .message
        relayout()
        thinkingStep += 1
    }

    private func stopThinking() {
        thinkingTimer?.invalidate()
        thinkingTimer = nil
    }

    private func stopTyping() {
        typingTimer?.invalidate()
        typingTimer = nil
    }

    // MARK: - Layout (one active region; bubble grows to fit)

    private func relayout() {
        let contentWidth = measuredContentWidth()
        let shapeWidth = contentWidth + spec.balloon.pad * 2

        messageLabel.isHidden = mode == .input
        inputScrollView.isHidden = mode != .input
        inputPlaceholderView.isHidden = mode != .input || !inputTextView.string.isEmpty
        choiceButtons.forEach { $0.isHidden = mode != .choices }

        var contentHeight: CGFloat = 0
        switch mode {
        case .input:
            contentHeight = measuredInputHeight(width: contentWidth)
        case .message:
            contentHeight = measuredLabelHeight(messageText.isEmpty ? "…" : messageText, width: contentWidth)
        case .choices:
            let promptHeight = measuredLabelHeight(messageText.isEmpty ? "…" : messageText, width: contentWidth)
            let buttonsHeight = choiceButtons.isEmpty ? 0 : CGFloat(choiceButtons.count) * 20 - 2
            contentHeight = promptHeight + (choiceButtons.isEmpty ? 0 : 7 + buttonsHeight)
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
        case .choices:
            let promptHeight = measuredLabelHeight(messageText.isEmpty ? "…" : messageText, width: contentWidth)
            messageLabel.frame = CGRect(
                x: contentRect.minX,
                y: contentRect.maxY - promptHeight,
                width: contentRect.width,
                height: promptHeight
            )
            messageLabel.stringValue = messageText
            var y = contentRect.maxY - promptHeight - 7 - 18
            for (index, button) in choiceButtons.enumerated() {
                button.isKeyboardFocused = index == selectedChoiceIndex
                button.frame = CGRect(x: contentRect.minX + 2, y: y, width: contentRect.width - 4, height: 18)
                y -= 20
            }
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
        case .choices:
            text = ([messageText] + choiceButtons.map(\.title)).joined(separator: "\n")
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

    private func clearChoices() {
        for button in choiceButtons {
            button.isKeyboardFocused = false
            button.removeFromSuperview()
        }
        choiceButtons = []
        selectedChoiceIndex = nil
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

    public static func readingAutoHideDelay(for text: String) -> TimeInterval {
        let wordsPerMinute = 200.0
        let wordCount = max(1, text.split(whereSeparator: \.isWhitespace).count)
        let sentencePauses = Double(text.filter { ".!?".contains($0) }.count) * 0.25
        let readTime = Double(wordCount) / wordsPerMinute * 60.0
        return min(24.0, max(3.5, readTime + sentencePauses + 1.5))
    }

    public static func spokenAutoHideDelay(visibleFor seconds: TimeInterval) -> TimeInterval {
        let minimumVisibleDuration = 4.0
        let finishedSpeakingGrace = 2.0
        return max(finishedSpeakingGrace, minimumVisibleDuration - max(0, seconds))
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

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard mode == .choices else {
            return false
        }
        guard let action = ClippyChoiceKeyboard.action(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            selectedIndex: selectedChoiceIndex,
            choiceCount: choiceButtons.count
        ) else {
            return false
        }
        switch action {
        case .select(let index):
            selectedChoiceIndex = index
            relayout()
        case .activate(let index):
            activateChoice(at: index)
        case .cancel:
            hide()
        }
        return true
    }

    private func activateChoice(at index: Int) {
        guard choiceButtons.indices.contains(index) else {
            return
        }
        choiceButtons[index].onClick?()
    }

}

enum ClippyChoiceKeyboardAction: Equatable {
    case select(Int)
    case activate(Int)
    case cancel
}

enum ClippyChoiceKeyboard {
    static func action(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        selectedIndex: Int?,
        choiceCount: Int
    ) -> ClippyChoiceKeyboardAction? {
        guard choiceCount > 0 else {
            return nil
        }
        if let numberIndex = choiceNumberIndex(charactersIgnoringModifiers, choiceCount: choiceCount) {
            return .activate(numberIndex)
        }
        switch keyCode {
        case 36, 49, 76:
            return .activate(selectedIndex ?? 0)
        case 48, 125:
            return .select(wrappedIndex(after: selectedIndex, delta: 1, count: choiceCount))
        case 126:
            return .select(wrappedIndex(after: selectedIndex, delta: -1, count: choiceCount))
        case 53:
            return .cancel
        default:
            return nil
        }
    }

    private static func choiceNumberIndex(_ characters: String?, choiceCount: Int) -> Int? {
        guard let character = characters?.first,
              character >= "1",
              character <= "9",
              let value = character.wholeNumberValue
        else {
            return nil
        }
        let index = value - 1
        return index < choiceCount ? index : nil
    }

    private static func wrappedIndex(after selectedIndex: Int?, delta: Int, count: Int) -> Int {
        guard let selectedIndex else {
            return delta >= 0 ? 0 : count - 1
        }
        return (selectedIndex + delta + count) % count
    }
}
