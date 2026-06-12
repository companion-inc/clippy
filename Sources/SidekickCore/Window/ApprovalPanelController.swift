import AppKit

/// The conscience surface: when the assistant wants to run a protected action
/// (shell, send, delete, ...), Sidekick shows what it wants to do and waits for an
/// explicit Approve / Deny before the tool runs.
public final class ApprovalPanelController: NSObject {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class PixelChoiceButton: NSButton {
        init(frame frameRect: NSRect, theme: MascotBalloonTheme) {
            super.init(frame: frameRect)
            isBordered = false
            wantsLayer = true
            layer?.backgroundColor = theme.fillColor.cgColor
            layer?.borderColor = theme.strokeColor.cgColor
            layer?.borderWidth = theme.borderWidth
            layer?.cornerRadius = 0
            font = SidekickBalloonStyle.font(12, theme: theme)
            contentTintColor = theme.textColor
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }
    }

    private static let buttonHeight: CGFloat = 24
    private static let buttonWidth: CGFloat = 78

    public let window: NSPanel
    private let theme: MascotTheme
    private let rootView = NSView(frame: .zero)
    private let balloonLayer: CAShapeLayer
    private let label = NSTextField(wrappingLabelWithString: "")
    private let deny: PixelChoiceButton
    private let approve: PixelChoiceButton
    private var onDecision: ((Bool) -> Void)?

    public init(theme: MascotTheme = .clippy) {
        self.theme = theme
        self.balloonLayer = SidekickBalloonStyle.makeShapeLayer(theme: theme.balloon)
        self.deny = PixelChoiceButton(frame: .zero, theme: theme.balloon)
        self.approve = PixelChoiceButton(frame: .zero, theme: theme.balloon)
        self.window = KeyPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: theme.balloon.approvalWidth, height: 120)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        rootView.wantsLayer = true
        rootView.layer?.addSublayer(balloonLayer)

        label.font = uiFont(12)
        label.textColor = theme.balloon.textColor
        label.maximumNumberOfLines = 0
        rootView.addSubview(label)

        deny.title = "No"
        deny.target = self
        deny.action = #selector(denyClicked)
        deny.keyEquivalent = "\u{1b}"
        rootView.addSubview(deny)

        approve.title = "Do it"
        approve.target = self
        approve.action = #selector(approveClicked)
        approve.keyEquivalent = "\r"
        rootView.addSubview(approve)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = WindowLevelPolicy.bubbleLevel
        window.isFloatingPanel = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = rootView
    }

    private func uiFont(_ size: CGFloat, bold: Bool = false) -> NSFont {
        SidekickBalloonStyle.font(size, bold: bold, theme: theme.balloon)
    }

    public func show(
        request: ApprovalRequest,
        anchoredTo mascotFrame: CGRect,
        onDecision: @escaping (Bool) -> Void
    ) {
        self.onDecision = onDecision

        var detail = request.reason
        if case let .string(command)? = request.invocation.arguments["command"] {
            detail += "\n\n$ \(command)"
        }
        label.stringValue = "Can I run \(request.invocation.name)?\n\(detail)"

        relayout()

        let size = window.frame.size
        let origin = CGPoint(
            x: mascotFrame.midX - size.width / 2,
            y: mascotFrame.maxY + 8
        )
        window.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func relayout() {
        let width = theme.balloon.approvalWidth
        let pad = theme.balloon.pad
        let contentWidth = width - pad * 2
        let labelHeight = measuredLabelHeight(label.stringValue, width: contentWidth)
        let contentHeight = labelHeight + 10 + Self.buttonHeight
        let height = theme.balloon.tailHeight + pad + contentHeight + pad

        window.setContentSize(CGSize(width: width, height: height))
        rootView.frame = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        balloonLayer.frame = rootView.bounds
        balloonLayer.path = SidekickBalloonStyle.path(size: rootView.bounds.size, theme: theme.balloon)

        let labelY = theme.balloon.tailHeight + pad + Self.buttonHeight + 10
        label.frame = CGRect(x: pad, y: labelY, width: contentWidth, height: labelHeight)

        let buttonY = theme.balloon.tailHeight + pad
        deny.frame = CGRect(x: pad, y: buttonY, width: Self.buttonWidth, height: Self.buttonHeight)
        approve.frame = CGRect(
            x: width - pad - Self.buttonWidth,
            y: buttonY,
            width: Self.buttonWidth,
            height: Self.buttonHeight
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

    public func hide() {
        window.orderOut(nil)
    }

    @objc private func approveClicked() {
        hide()
        onDecision?(true)
    }

    @objc private func denyClicked() {
        hide()
        onDecision?(false)
    }
}
