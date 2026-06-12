import AppKit

/// The conscience surface: when the assistant wants to run a protected action
/// (shell, send, delete, …), Clippy shows what it wants to do and waits for an
/// explicit Approve / Deny before the tool runs.
public final class ApprovalPanelController: NSObject {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private static let balloonColor = NSColor(calibratedRed: 1.0, green: 1.0, blue: 225.0 / 255.0, alpha: 1)

    public let window: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private var onDecision: ((Bool) -> Void)?

    public override init() {
        let size = CGSize(width: 300, height: 120)
        self.window = KeyPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = Self.balloonColor.cgColor
        view.layer?.cornerRadius = 6
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.black.cgColor

        label.frame = CGRect(x: 12, y: 44, width: size.width - 24, height: 66)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .black
        label.maximumNumberOfLines = 4
        view.addSubview(label)

        let deny = NSButton(title: "Deny", target: self, action: #selector(denyClicked))
        deny.frame = CGRect(x: 12, y: 10, width: 120, height: 26)
        deny.bezelStyle = .rounded
        deny.keyEquivalent = "\u{1b}"
        view.addSubview(deny)

        let approve = NSButton(title: "Approve", target: self, action: #selector(approveClicked))
        approve.frame = CGRect(x: size.width - 132, y: 10, width: 120, height: 26)
        approve.bezelStyle = .rounded
        approve.keyEquivalent = "\r"
        view.addSubview(approve)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = WindowLevelPolicy.bubbleLevel
        window.isFloatingPanel = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view
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
        label.stringValue = "Clippy wants to run \(request.invocation.name).\n\(detail)"

        let size = window.frame.size
        let origin = CGPoint(
            x: mascotFrame.midX - size.width / 2,
            y: mascotFrame.maxY + 8
        )
        window.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
