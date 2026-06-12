import AppKit

/// A small text field anchored under the character: click Clippy, type a
/// question, press Return to ask. Styled like the speech balloon.
public final class AskInputController: NSObject, NSTextFieldDelegate {
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private static let balloonColor = NSColor(calibratedRed: 1.0, green: 1.0, blue: 225.0 / 255.0, alpha: 1)

    public let window: NSPanel
    private let field = NSTextField()
    private var onSubmit: ((String) -> Void)?
    private var onCancel: (() -> Void)?

    public override init() {
        let size = CGSize(width: 280, height: 40)
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

        field.frame = CGRect(x: 10, y: 9, width: size.width - 20, height: 22)
        field.font = .systemFont(ofSize: 13)
        field.textColor = .black
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "Ask Clippy…"
        field.delegate = self
        view.addSubview(field)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = WindowLevelPolicy.bubbleLevel
        window.isFloatingPanel = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view
    }

    public func show(
        anchoredTo mascotFrame: CGRect,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        field.stringValue = ""

        let size = window.frame.size
        let origin = CGPoint(
            x: mascotFrame.midX - size.width / 2,
            y: mascotFrame.maxY + 8
        )
        window.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
    }

    public func hide() {
        window.orderOut(nil)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            hide()
            if !text.isEmpty {
                onSubmit?(text)
            } else {
                onCancel?()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            onCancel?()
            return true
        default:
            return false
        }
    }
}
