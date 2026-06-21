import AppKit

/// Sidekick's one and only bubble. It shows exactly one thing at a time:
///   • a single message line (greeting or the latest reply), or
///   • the input field (when you click Sidekick).
/// While Sidekick is thinking, the bubble shows the current backend phase instead
/// of leaving the user with anonymous dots. Click Sidekick to open the input;
/// click away and it disappears. Type face is Microsoft Sans Serif (the modern
/// name for the MS Sans Serif the original balloon used).
public final class SidekickBubbleController: NSObject, NSTextViewDelegate, NSWindowDelegate {
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

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if onKeyDown?(event) == true {
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

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
        var onEditingCommand: ((NSEvent) -> Bool)?

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if onEditingCommand?(event) == true {
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        override func keyDown(with event: NSEvent) {
            if onEditingCommand?(event) == true {
                return
            }
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
        private static let shortcutHintWidth: CGFloat = 9
        private static let shortcutHintGap: CGFloat = 4

        var title: String { didSet { needsDisplay = true } }
        var shortcutLabel: String? { didSet { needsDisplay = true } }
        var onClick: (() -> Void)?
        var isKeyboardFocused = false { didSet { needsDisplay = true } }
        private var pressed = false

        override var isFlipped: Bool { true }

        init(title: String, shortcutLabel: String?) {
            self.title = title
            self.shortcutLabel = shortcutLabel
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
            paragraph.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: RetroFont.ui(11),
                .foregroundColor: RetroPalette.text,
                .paragraphStyle: paragraph,
            ]
            let shortcutWidth: CGFloat = shortcutLabel == nil ? 0 : Self.shortcutHintWidth
            let shortcutGap: CGFloat = shortcutLabel == nil ? 0 : Self.shortcutHintGap
            let label = title as NSString
            let textSize = label.size(withAttributes: attrs)
            let textRect = NSRect(
                x: 16 + offset,
                y: max(0, (bounds.height - textSize.height) / 2) + offset,
                width: max(0, bounds.width - 16 - shortcutWidth - shortcutGap),
                height: textSize.height
            )
            label.draw(in: textRect, withAttributes: attrs)

            if let shortcutLabel {
                let shortcutParagraph = NSMutableParagraphStyle()
                shortcutParagraph.alignment = .right
                let shortcutAttrs: [NSAttributedString.Key: Any] = [
                    .font: RetroFont.ui(8),
                    .foregroundColor: RetroPalette.grayText.withAlphaComponent(0.72),
                    .paragraphStyle: shortcutParagraph,
                ]
                let shortcutRect = NSRect(
                    x: bounds.width - Self.shortcutHintWidth - 3 + offset,
                    y: 4 + offset,
                    width: Self.shortcutHintWidth,
                    height: 10
                )
                (shortcutLabel as NSString).draw(
                    in: shortcutRect,
                    withAttributes: shortcutAttrs
                )
            }

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

    private final class RichImageCardView: NSView {
        private let imageView = NSImageView()
        private let captionLabel = NSTextField(labelWithString: "")
        private let sourceLabel = NSTextField(labelWithString: "")
        private var imageTask: URLSessionDataTask?
        private var openURL: URL?
        private var representedImageURLString = ""
        private static let inset: CGFloat = 5
        private static let imageHeight: CGFloat = 94
        private static let labelHeight: CGFloat = 15

        override var isFlipped: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true

            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.72).cgColor
            addSubview(imageView)

            captionLabel.font = RetroFont.ui(10, bold: true)
            captionLabel.textColor = RetroPalette.text
            captionLabel.lineBreakMode = .byTruncatingTail
            addSubview(captionLabel)

            sourceLabel.font = RetroFont.ui(9)
            sourceLabel.textColor = RetroPalette.grayText
            sourceLabel.lineBreakMode = .byTruncatingTail
            addSubview(sourceLabel)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func configure(_ card: SidekickRichReply.ImageCard) {
            imageTask?.cancel()
            imageTask = nil
            representedImageURLString = card.imageURLString
            imageView.image = nil
            captionLabel.stringValue = card.caption.isEmpty ? "Image" : card.caption

            let sourceURL = card.sourceURLString.flatMap(Self.url(from:))
            let imageURL = Self.url(from: card.imageURLString)
            openURL = sourceURL ?? imageURL
            let sourceTitle = card.sourceTitle
                ?? sourceURL.flatMap(Self.hostTitle(from:))
                ?? imageURL.flatMap(Self.hostTitle(from:))
                ?? "Image source"
            sourceLabel.stringValue = "Source: \(sourceTitle)"
            sourceLabel.toolTip = (sourceURL ?? imageURL)?.absoluteString
            toolTip = sourceLabel.toolTip
            loadImage(from: card.imageURLString)
        }

        func preferredHeight(width _: CGFloat) -> CGFloat {
            Self.inset * 2 + Self.imageHeight + Self.labelHeight * 2 + 3
        }

        override func layout() {
            super.layout()
            let inset = Self.inset
            let imageWidth = max(1, bounds.width - inset * 2)
            imageView.frame = CGRect(x: inset, y: inset, width: imageWidth, height: Self.imageHeight)
            captionLabel.frame = CGRect(
                x: inset,
                y: imageView.frame.maxY + 3,
                width: imageWidth,
                height: Self.labelHeight
            )
            sourceLabel.frame = CGRect(
                x: inset,
                y: captionLabel.frame.maxY,
                width: imageWidth,
                height: Self.labelHeight
            )
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            RetroPalette.fieldBackground.setFill()
            bounds.fill()
            RetroBezel.draw(.field, in: bounds)
        }

        override func mouseUp(with event: NSEvent) {
            guard let openURL else { return }
            NSWorkspace.shared.open(openURL)
        }

        func cancelLoad() {
            imageTask?.cancel()
            imageTask = nil
        }

        private func loadImage(from value: String) {
            guard let url = Self.url(from: value) else {
                sourceLabel.stringValue = "Image unavailable"
                return
            }
            if url.isFileURL {
                imageView.image = NSImage(contentsOf: url)
                if imageView.image == nil {
                    sourceLabel.stringValue = "Image unavailable"
                }
                return
            }
            let expected = representedImageURLString
            imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data,
                      let image = NSImage(data: data) else {
                    return
                }
                DispatchQueue.main.async {
                    guard let self,
                          self.representedImageURLString == expected else {
                        return
                    }
                    self.imageView.image = image
                }
            }
            imageTask?.resume()
        }

        private static func url(from value: String) -> URL? {
            if value.hasPrefix("/") {
                return URL(fileURLWithPath: value)
            }
            return URL(string: value)
        }

        private static func hostTitle(from url: URL) -> String? {
            guard let host = url.host, host.isEmpty == false else {
                return url.isFileURL ? "Local image" : nil
            }
            return host.replacingOccurrences(of: "www.", with: "")
        }
    }

    private enum Mode { case message, input, choices }
    private enum InputEditingCommand { case selectAll, copy, cut, paste }

    private func uiFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
        SidekickBalloonStyle.font(size, bold: bold, spec: spec.balloon)
    }

    public let window: NSPanel
    private let spec: SidekickSpec
    private let root = NSView()
    private let balloonLayer: CAShapeLayer
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let citationsLabel = NSTextField(wrappingLabelWithString: "")
    private let inputScrollView = NSScrollView()
    private let inputTextView = InputTextView(frame: .zero)
    private let inputPlaceholderView = NSTextView(frame: .zero)
    private var choiceButtons: [BalloonChoiceButton] = []
    private var imageCardViews: [RichImageCardView] = []
    private var selectedChoiceIndex: Int?

    private var mode: Mode = .message
    private var messageText = ""
    private var richReply = SidekickRichReply(text: "")
    private var onSend: ((String) -> Void)?
    private var anchorFrame: CGRect = .zero
    private weak var anchorWindow: NSWindow?
    private var autoHideTimer: Timer?
    private var typingTimer: Timer?
    private var choiceTypingActive = false
    private var inputDismissedByAnchorClickAt: TimeInterval?
    private static let anchorClickDismissalReplayWindow: TimeInterval = 0.35
    public static let proactiveChoiceAutoHideDelay: TimeInterval = 30

    public init(spec: SidekickSpec = .current) {
        self.spec = spec
        self.balloonLayer = SidekickBalloonStyle.makeShapeLayer(spec: spec.balloon)
        self.window = KeyPanel(
            contentRect: CGRect(x: 0, y: 0, width: spec.balloon.minWidth, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        (window as? KeyPanel)?.onKeyDown = { [weak self] event in
            guard let self else { return false }
            if self.handleKeyDown(event) {
                return true
            }
            return self.receiveExternalInputKey(event)
        }

        root.frame = window.frame
        root.wantsLayer = true
        root.layer?.addSublayer(balloonLayer)

        messageLabel.font = uiFont(spec.balloon.messageFontSize)
        messageLabel.textColor = spec.balloon.textColor
        messageLabel.maximumNumberOfLines = 0
        root.addSubview(messageLabel)

        citationsLabel.font = uiFont(10)
        citationsLabel.textColor = spec.balloon.mutedTextColor
        citationsLabel.maximumNumberOfLines = 2
        citationsLabel.isHidden = true
        root.addSubview(citationsLabel)

        configureInputTextView(inputTextView, textColor: spec.balloon.textColor)
        inputTextView.delegate = self
        inputTextView.onSubmit = { [weak self] in self?.submitInput() }
        inputTextView.onCancel = { [weak self] in self?.hide() }
        inputTextView.onEditingCommand = { [weak self] event in self?.handleInputEditingCommand(event) ?? false }

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
    public var isPresentingChoices: Bool { window.isVisible && (mode == .choices || choiceTypingActive) }
    var debugInputText: String { inputTextView.string }
    var debugSelectedRange: NSRange { inputTextView.selectedRange() }
    var debugChoiceShortcutLabels: [String?] { choiceButtons.map(\.shortcutLabel) }
    var debugRichImageCardCount: Int { imageCardViews.count }
    var debugCitationText: String { citationsLabel.stringValue }
    var debugMessageLineBreakMode: NSLineBreakMode { messageLabel.lineBreakMode }
    var debugMessageMaximumNumberOfLines: Int { messageLabel.maximumNumberOfLines }

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
        clearRichReply()
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

    /// Click Sidekick: show only the input, focused. Click-away dismisses it.
    public func openInput(prefilledText: String = "") {
        stopTyping()
        stopThinking()
        cancelAutoHide()
        clearChoices()
        mode = .input
        inputTextView.string = prefilledText
        relayout()
        attachToAnchorWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(inputTextView)
        inputTextView.setSelectedRange(NSRange(location: (prefilledText as NSString).length, length: 0))
        inputTextView.scrollRangeToVisible(inputTextView.selectedRange())
    }

    @discardableResult
    public func receiveExternalInputKey(_ event: NSEvent) -> Bool {
        guard !isPresentingChoices else {
            return receiveChoiceKey(event) ?? true
        }
        if handleInputEditingCommand(event) {
            return true
        }
        guard Self.acceptsExternalInputKey(
            keyCode: event.keyCode,
            characters: event.characters,
            modifierFlags: event.modifierFlags,
            inputAlreadyOpen: isInputMode
        ) else {
            return false
        }
        if !isInputMode {
            openInput()
        } else {
            focusInput()
        }
        switch event.keyCode {
        case 36, 76:
            submitInput()
        case 53:
            hide()
        case 51:
            inputTextView.deleteBackward(nil)
            relayout()
        case 117:
            inputTextView.deleteForward(nil)
            relayout()
        default:
            guard let characters = event.characters, !characters.isEmpty else { return false }
            inputTextView.insertText(characters, replacementRange: inputTextView.selectedRange())
            relayout()
        }
        return true
    }

    @discardableResult
    public func receiveChoiceKey(_ event: NSEvent) -> Bool? {
        guard mode == .choices else {
            return choiceTypingActive ? false : nil
        }
        return handleKeyDown(event)
    }

    public nonisolated static func acceptsInputEditingCommand(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        inputEditingCommand(charactersIgnoringModifiers: charactersIgnoringModifiers, modifierFlags: modifierFlags) != nil
    }

    private func handleInputEditingCommand(_ event: NSEvent) -> Bool {
        guard let command = Self.inputEditingCommand(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ) else {
            return false
        }
        if !isInputMode {
            guard command == .paste else { return false }
            openInput()
        } else {
            focusInput()
        }
        switch command {
        case .selectAll:
            inputTextView.selectAll(nil)
        case .copy:
            inputTextView.copy(nil)
        case .cut:
            inputTextView.cut(nil)
            relayout()
        case .paste:
            if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                inputTextView.insertText(pasted, replacementRange: inputTextView.selectedRange())
                relayout()
            }
        }
        return true
    }

    private nonisolated static func inputEditingCommand(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> InputEditingCommand? {
        guard modifierFlags.contains(.command) else { return nil }
        let disallowed: NSEvent.ModifierFlags = [.control, .option, .function]
        guard modifierFlags.intersection(disallowed).isEmpty else { return nil }
        switch charactersIgnoringModifiers?.lowercased() {
        case "a": return .selectAll
        case "c": return .copy
        case "x": return .cut
        case "v": return .paste
        default: return nil
        }
    }

    public nonisolated static func acceptsExternalInputKey(
        keyCode: UInt16,
        characters: String?,
        modifierFlags: NSEvent.ModifierFlags,
        inputAlreadyOpen: Bool
    ) -> Bool {
        ExternalInputKeyFilter.accepts(
            keyCode: keyCode,
            characters: characters,
            modifierFlags: modifierFlags,
            inputAlreadyOpen: inputAlreadyOpen
        )
    }

    public func focusInput() {
        guard mode == .input, window.isVisible else {
            openInput()
            return
        }
        stopTyping()
        stopThinking()
        cancelAutoHide()
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
    public func showReply(_ text: String, autoHide: TimeInterval? = nil, allowsRichMedia: Bool = true) {
        stopTyping()
        stopThinking()
        clearChoices()
        let shouldStayVisible: Bool
        if allowsRichMedia {
            let reply = SidekickRichReply.parse(text)
            shouldStayVisible = reply.hasRichMedia
            applyRichReply(reply)
        } else {
            shouldStayVisible = false
            clearRichReply()
            messageText = text
        }
        mode = .message
        relayout()
        attachToAnchorWindow()
        window.orderFrontRegardless()
        scheduleAutoHide(shouldStayVisible ? nil : autoHide)
    }

    public func showReplyForReading(_ text: String) {
        showReply(text, autoHide: Self.readingAutoHideDelay(for: text))
    }

    public func showStatus(_ text: String) {
        showReply(text, allowsRichMedia: false)
    }

    public func showChoices(_ prompt: String, choices: [Choice], autoHide: TimeInterval? = nil) {
        stopTyping()
        stopThinking()
        cancelAutoHide()
        clearChoices()
        clearRichReply()
        choiceTypingActive = false
        messageText = prompt
        mode = .choices
        choiceButtons = choices.enumerated().map { index, choice in
            let button = BalloonChoiceButton(title: choice.title, shortcutLabel: Self.shortcutLabel(forChoiceAt: index))
            button.onClick = choice.action
            root.addSubview(button)
            return button
        }
        selectedChoiceIndex = choices.isEmpty ? nil : 0
        relayout()
        attachToAnchorWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        scheduleAutoHide(autoHide)
    }

    public func showChoicesTyping(_ prompt: String, choices: [Choice], autoHide: TimeInterval? = nil) {
        stopTyping()
        stopThinking()
        cancelAutoHide()
        clearChoices()
        clearRichReply()
        choiceTypingActive = true
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
                self.choiceTypingActive = false
                self.showChoices(prompt, choices: choices, autoHide: autoHide)
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

    func recordInputDismissedByAnchorClick(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        inputDismissedByAnchorClickAt = now
    }

    @discardableResult
    public func consumeRecentInputDismissalByAnchorClick(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let dismissedAt = inputDismissedByAnchorClickAt else {
            return false
        }
        inputDismissedByAnchorClickAt = nil
        return now - dismissedAt <= Self.anchorClickDismissalReplayWindow
    }

    // MARK: - Thinking indicator

    private var thinkingTimer: Timer?
    private var thinkingStep = 0
    private var thinkingStatus = "Thinking"
    private let thinkingSuffixes = ["", ".", "..", "..."]

    /// Animated status bubble while Sidekick is thinking — shown alongside the
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
        clearRichReply()
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
        choiceTypingActive = false
    }

    private func applyRichReply(_ reply: SidekickRichReply) {
        clearRichReply()
        richReply = reply
        messageText = reply.text
        citationsLabel.stringValue = citationSummary(for: reply)
        citationsLabel.toolTip = citationTooltip(for: reply)
        for card in reply.imageCards.prefix(4) {
            let cardView = RichImageCardView()
            cardView.configure(card)
            imageCardViews.append(cardView)
            root.addSubview(cardView)
        }
    }

    private func clearRichReply() {
        richReply = SidekickRichReply(text: "")
        citationsLabel.stringValue = ""
        citationsLabel.toolTip = nil
        citationsLabel.isHidden = true
        for view in imageCardViews {
            view.cancelLoad()
            view.removeFromSuperview()
        }
        imageCardViews = []
    }

    private func citationSummary(for reply: SidekickRichReply) -> String {
        let imageSourceURLs = Set(reply.imageCards.compactMap(\.sourceURLString))
        let visible = reply.citations
            .filter { imageSourceURLs.contains($0.urlString) == false }
            .prefix(3)
        guard visible.isEmpty == false else { return "" }
        return "Sources: " + visible.map(\.title).joined(separator: ", ")
    }

    private func citationTooltip(for reply: SidekickRichReply) -> String? {
        let imageSourceURLs = Set(reply.imageCards.compactMap(\.sourceURLString))
        let urls = reply.citations
            .filter { imageSourceURLs.contains($0.urlString) == false }
            .map(\.urlString)
        return urls.isEmpty ? nil : urls.joined(separator: "\n")
    }

    // MARK: - Layout (one active region; bubble grows to fit)

    private func relayout() {
        let contentWidth = measuredContentWidth()
        let shapeWidth = contentWidth + spec.balloon.pad * 2

        let messageHasText = messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasImageCards = mode == .message && imageCardViews.isEmpty == false
        let hasCitationText = mode == .message && citationsLabel.stringValue.isEmpty == false
        messageLabel.isHidden = mode == .input || (hasImageCards && messageHasText == false)
        citationsLabel.isHidden = hasCitationText == false
        imageCardViews.forEach { $0.isHidden = mode != .message }
        inputScrollView.isHidden = mode != .input
        inputPlaceholderView.isHidden = mode != .input || !inputTextView.string.isEmpty
        choiceButtons.forEach { $0.isHidden = mode != .choices }

        var contentHeight: CGFloat = 0
        switch mode {
        case .input:
            contentHeight = measuredInputHeight(width: contentWidth)
        case .message:
            if hasImageCards || hasCitationText {
                contentHeight = richMessageHeight(width: contentWidth, hasText: messageHasText)
            } else {
                contentHeight = measuredLabelHeight(messageText.isEmpty ? "…" : messageText, width: contentWidth)
            }
        case .choices:
            let promptHeight = measuredChoicePromptHeight(width: contentWidth)
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
        balloonLayer.path = SidekickBalloonStyle.path(size: shapeSize, spec: spec.balloon)

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
            messageLabel.maximumNumberOfLines = 0
            messageLabel.lineBreakMode = .byWordWrapping
            if hasImageCards || hasCitationText {
                layoutRichMessage(in: contentRect, hasText: messageHasText)
            } else {
                messageLabel.frame = contentRect
                messageLabel.stringValue = messageText
            }
        case .choices:
            let promptHeight = measuredChoicePromptHeight(width: contentWidth)
            messageLabel.maximumNumberOfLines = 0
            messageLabel.lineBreakMode = .byWordWrapping
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
        let maxWidth: CGFloat
        switch mode {
        case .input:
            text = inputTextView.string.isEmpty ? inputPlaceholderView.string : inputTextView.string
            fontSize = spec.balloon.inputFontSize
            maxWidth = spec.balloon.maxWidth
        case .message:
            text = messageText.isEmpty ? "…" : messageText
            fontSize = spec.balloon.messageFontSize
            maxWidth = imageCardViews.isEmpty ? spec.balloon.maxWidth : max(spec.balloon.maxWidth, 350)
        case .choices:
            text = ([messageText] + choiceButtons.map { button in
                button.shortcutLabel == nil ? button.title : "\(button.title)    \(button.shortcutLabel!)"
            }).joined(separator: "\n")
            fontSize = spec.balloon.messageFontSize
            maxWidth = max(spec.balloon.maxWidth, 360)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = lines.map { String($0) }.max { $0.count < $1.count } ?? text
        let attributed = NSAttributedString(string: longest, attributes: [.font: uiFont(fontSize)])
        let width = ceil(attributed.size().width) + 4
        return min(
            maxWidth - spec.balloon.pad * 2,
            max(spec.balloon.minWidth - spec.balloon.pad * 2, width, imageCardViews.isEmpty ? 0 : 270)
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

    private func measuredChoicePromptHeight(width: CGFloat) -> CGFloat {
        let text = messageText.isEmpty ? "…" : messageText
        return measuredLabelHeight(text, width: width)
    }

    private func richMessageHeight(width: CGFloat, hasText: Bool) -> CGFloat {
        let textHeight = hasText ? measuredLabelHeight(messageText, width: width) : 0
        let imageHeight = imageCardViews.reduce(CGFloat(0)) { total, view in
            total + view.preferredHeight(width: width)
        }
        let imageGaps = imageCardViews.isEmpty ? 0 : CGFloat(max(0, imageCardViews.count - 1)) * 6
        let citationHeight = citationsLabel.stringValue.isEmpty ? 0 : measuredCitationHeight(width: width)
        let textGap = hasText && (imageCardViews.isEmpty == false || citationHeight > 0) ? CGFloat(7) : 0
        let citationGap = citationHeight > 0 && imageCardViews.isEmpty == false ? CGFloat(5) : 0
        return max(1, textHeight + textGap + imageHeight + imageGaps + citationGap + citationHeight)
    }

    private func measuredCitationHeight(width: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: citationsLabel.stringValue, attributes: [.font: uiFont(10)])
        let rect = attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height) + 1
    }

    private func layoutRichMessage(in contentRect: CGRect, hasText: Bool) {
        var y = contentRect.maxY
        if hasText {
            let textHeight = measuredLabelHeight(messageText, width: contentRect.width)
            y -= textHeight
            messageLabel.frame = CGRect(
                x: contentRect.minX,
                y: y,
                width: contentRect.width,
                height: textHeight
            )
            messageLabel.stringValue = messageText
            y -= 7
        } else {
            messageLabel.stringValue = ""
        }

        for view in imageCardViews {
            let height = view.preferredHeight(width: contentRect.width)
            y -= height
            view.frame = CGRect(
                x: contentRect.minX,
                y: y,
                width: contentRect.width,
                height: height
            )
            y -= 6
        }

        if citationsLabel.stringValue.isEmpty == false {
            if imageCardViews.isEmpty == false {
                y += 1
            }
            let height = measuredCitationHeight(width: contentRect.width)
            y -= height
            citationsLabel.frame = CGRect(
                x: contentRect.minX,
                y: y,
                width: contentRect.width,
                height: height
            )
        }
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
        guard mode == .input else { return }
        let dismissedByAnchorClick = currentEventIsMouseDownInAnchorWindow()
        hide()
        if dismissedByAnchorClick {
            recordInputDismissedByAnchorClick()
        }
    }

    private func currentEventIsMouseDownInAnchorWindow() -> Bool {
        guard
            let anchorWindow,
            let event = NSApp.currentEvent,
            event.windowNumber == anchorWindow.windowNumber
        else {
            return false
        }
        return event.type == .leftMouseDown
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
        guard let action = SidekickChoiceKeyboard.action(
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

    private static func shortcutLabel(forChoiceAt index: Int) -> String? {
        guard index >= 0, index < 9 else {
            return nil
        }
        return String(index + 1)
    }
}

enum SidekickChoiceKeyboardAction: Equatable {
    case select(Int)
    case activate(Int)
    case cancel
}

enum SidekickChoiceKeyboard {
    static func action(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        selectedIndex: Int?,
        choiceCount: Int
    ) -> SidekickChoiceKeyboardAction? {
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
