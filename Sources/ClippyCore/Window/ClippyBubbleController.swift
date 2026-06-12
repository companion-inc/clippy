import AppKit

/// Clippy's one and only bubble. It shows exactly one thing at a time:
///   • a single message line (greeting, "thinking", or the latest reply), or
///   • the input field (when you click Clippy), or
///   • the full history (when you press "show history").
/// Click Clippy to open the input; click away and it disappears. Same balloon
/// for everything — greeting and chat are the same surface.
public final class ClippyBubbleController: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private enum Mode { case message, input, history }
    private enum Speaker { case user, clippy }
    private struct Line { let speaker: Speaker; let text: String }

    private static let balloonColor = NSColor(calibratedRed: 1.0, green: 1.0, blue: 225.0 / 255.0, alpha: 1)
    private static let width: CGFloat = 280
    private static let pad: CGFloat = 12
    private static let tailHeight: CGFloat = 12
    private static let maxHistoryHeight: CGFloat = 300

    public let window: NSPanel
    private let balloonLayer = CAShapeLayer()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let inputField = NSTextField()
    private let scrollView = NSScrollView()
    private let transcriptView = NSTextView()
    private let historyButton = NSButton()

    private var mode: Mode = .message
    private var history: [Line] = []
    private var messageText = ""
    private var onSend: ((String) -> Void)?
    private var anchorFrame: CGRect = .zero
    private var autoHideTimer: Timer?
    private var thinkingTimer: Timer?
    private var thinkingDots = 0

    public override init() {
        self.window = KeyPanel(
            contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let root = NSView(frame: window.frame)
        root.wantsLayer = true
        root.layer?.addSublayer(balloonLayer)
        balloonLayer.fillColor = Self.balloonColor.cgColor
        balloonLayer.strokeColor = NSColor.black.cgColor
        balloonLayer.lineWidth = 1

        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .black
        messageLabel.maximumNumberOfLines = 0
        root.addSubview(messageLabel)

        inputField.font = .systemFont(ofSize: 14)
        inputField.textColor = .black
        inputField.drawsBackground = false
        inputField.isBordered = false
        inputField.focusRingType = .none
        inputField.placeholderString = "Ask Clippy…"
        inputField.delegate = self
        inputField.isHidden = true
        root.addSubview(inputField)

        transcriptView.isEditable = false
        transcriptView.isSelectable = true
        transcriptView.drawsBackground = false
        transcriptView.textContainerInset = NSSize(width: 2, height: 2)
        transcriptView.isHorizontallyResizable = false
        transcriptView.isVerticallyResizable = true
        transcriptView.textContainer?.widthTracksTextView = true
        transcriptView.autoresizingMask = [.width]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = transcriptView
        scrollView.isHidden = true
        root.addSubview(scrollView)

        historyButton.isBordered = false
        historyButton.font = .systemFont(ofSize: 10)
        historyButton.contentTintColor = NSColor(calibratedWhite: 0.35, alpha: 1)
        historyButton.target = self
        historyButton.action = #selector(historyButtonClicked)
        historyButton.isHidden = true
        root.addSubview(historyButton)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = WindowLevelPolicy.bubbleLevel
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.contentView = root
    }

    public var isVisible: Bool { window.isVisible }
    public var isInputMode: Bool { mode == .input && window.isVisible }

    /// Where Clippy is, so the tail always points at it.
    public func setAnchor(_ frame: CGRect) {
        anchorFrame = frame
        if window.isVisible { positionWindow() }
    }

    /// Stable send handler; set once at startup.
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
        window.orderFrontRegardless()
        scheduleAutoHide(autoHide)
    }

    /// Click-Clippy: show only the input, focused. Click-away dismisses it.
    public func openInput() {
        cancelAutoHide()
        stopThinking()
        mode = .input
        relayout()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(inputField)
    }

    public func toggleInput() {
        if mode == .input && window.isVisible {
            hide()
        } else {
            openInput()
        }
    }

    /// User sent a line — record it, switch to the thinking shimmer.
    public func showThinking(forUserLine userLine: String) {
        history.append(Line(speaker: .user, text: userLine))
        cancelAutoHide()
        mode = .message
        thinkingDots = 0
        messageText = "Clippy is thinking"
        relayout()
        window.orderFrontRegardless()
        thinkingTimer?.invalidate()
        thinkingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.thinkingDots = (self.thinkingDots + 1) % 4
            self.messageLabel.stringValue = "Clippy is thinking" + String(repeating: ".", count: self.thinkingDots)
        }
    }

    /// Reply arrived — replace everything with just the reply.
    public func showReply(_ text: String) {
        stopThinking()
        history.append(Line(speaker: .clippy, text: text))
        messageText = text
        mode = .message
        relayout()
        window.orderFrontRegardless()
    }

    public func hide() {
        cancelAutoHide()
        stopThinking()
        window.orderOut(nil)
    }

    // MARK: - History toggle

    @objc private func historyButtonClicked() {
        mode = (mode == .history) ? .message : .history
        relayout()
    }

    public func debugToggleExpanded() { historyButtonClicked() }

    // MARK: - Layout (one active region; bubble grows to fit)

    private func relayout() {
        let contentWidth = Self.width - Self.pad * 2
        let hasHistory = history.count >= 2
        let showButton = hasHistory && mode != .input

        messageLabel.isHidden = mode != .message
        inputField.isHidden = mode != .input
        scrollView.isHidden = mode != .history
        historyButton.isHidden = !showButton

        var contentHeight: CGFloat = 0
        switch mode {
        case .input:
            contentHeight = 24
        case .message:
            contentHeight = measuredLabelHeight(messageText.isEmpty ? "…" : messageText, width: contentWidth)
        case .history:
            let transcript = rebuildTranscript()
            let measured = transcript.boundingRect(
                with: NSSize(width: contentWidth - 8, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
            contentHeight = min(ceil(measured) + 10, Self.maxHistoryHeight)
        }

        let buttonH: CGFloat = showButton ? 14 : 0
        let buttonGap: CGFloat = showButton ? 6 : 0
        let windowHeight = Self.tailHeight + Self.pad + buttonH + buttonGap + contentHeight + Self.pad

        window.setContentSize(CGSize(width: Self.width, height: windowHeight))
        balloonLayer.frame = CGRect(origin: .zero, size: CGSize(width: Self.width, height: windowHeight))
        balloonLayer.path = Self.balloonPath(size: CGSize(width: Self.width, height: windowHeight))

        let contentY = Self.tailHeight + Self.pad
        let contentRect = CGRect(x: Self.pad, y: contentY, width: contentWidth, height: contentHeight)

        switch mode {
        case .input:
            inputField.frame = contentRect
        case .message:
            messageLabel.frame = contentRect
            if thinkingTimer == nil { messageLabel.stringValue = messageText }
        case .history:
            scrollView.frame = contentRect
            transcriptView.minSize = NSSize(width: 0, height: contentHeight)
            transcriptView.maxSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
            transcriptView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
            transcriptView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
            transcriptView.scrollToEndOfDocument(nil)
        }

        if showButton {
            historyButton.title = mode == .history ? "▾ hide history" : "▸ show history"
            historyButton.sizeToFit()
            historyButton.frame = CGRect(
                x: Self.width - Self.pad - historyButton.frame.width,
                y: contentY + contentHeight + buttonGap,
                width: historyButton.frame.width,
                height: buttonH
            )
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

    private func measuredLabelHeight(_ text: String, width: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let rect = attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(rect.height) + 2
    }

    @discardableResult
    private func rebuildTranscript() -> NSAttributedString {
        let full = NSMutableAttributedString()
        for (index, line) in history.enumerated() {
            if index > 0 { full.append(NSAttributedString(string: "\n\n")) }
            let prefix = line.speaker == .user ? "You: " : "Clippy: "
            let prefixColor: NSColor = line.speaker == .user
                ? NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.6, alpha: 1)
                : NSColor(calibratedRed: 0.5, green: 0.25, blue: 0.0, alpha: 1)
            full.append(NSAttributedString(string: prefix, attributes: [
                .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: prefixColor,
            ]))
            full.append(NSAttributedString(string: line.text, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black,
            ]))
        }
        transcriptView.textStorage?.setAttributedString(full)
        return full
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

    private func stopThinking() {
        thinkingTimer?.invalidate()
        thinkingTimer = nil
    }

    // MARK: - Click-away dismissal

    public func windowDidResignKey(_ notification: Notification) {
        // Clicking outside while typing should put the input away.
        if mode == .input { hide() }
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            inputField.stringValue = ""
            if !text.isEmpty { onSend?(text) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }

    private static func balloonPath(size: CGSize) -> CGPath {
        let inset: CGFloat = 0.5
        let left = inset, right = size.width - inset
        let bottom = tailHeight, top = size.height - inset
        let r: CGFloat = 7
        let tailLeftX = size.width * 0.5 - 8
        let tailRightX = size.width * 0.5 + 8
        let tipX = size.width * 0.5 - 4

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + r, y: bottom))
        path.addLine(to: CGPoint(x: tailLeftX, y: bottom))
        path.addLine(to: CGPoint(x: tipX, y: inset))
        path.addLine(to: CGPoint(x: tailRightX, y: bottom))
        path.addLine(to: CGPoint(x: right - r, y: bottom))
        path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right, y: bottom + r), radius: r)
        path.addLine(to: CGPoint(x: right, y: top - r))
        path.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right - r, y: top), radius: r)
        path.addLine(to: CGPoint(x: left + r, y: top))
        path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left, y: top - r), radius: r)
        path.addLine(to: CGPoint(x: left, y: bottom + r))
        path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left + r, y: bottom), radius: r)
        path.closeSubpath()
        return path
    }
}
