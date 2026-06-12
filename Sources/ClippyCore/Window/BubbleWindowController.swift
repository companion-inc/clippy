import AppKit

public final class BubbleWindowController {
    public let window: NSWindow
    private let label = NSTextField(labelWithString: "")

    public init() {
        self.window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 160, height: 42),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        let view = NSView(frame: CGRect(x: 0, y: 0, width: 160, height: 42))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor

        label.frame = CGRect(x: 10, y: 8, width: 140, height: 26)
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        view.addSubview(label)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = WindowLevelPolicy.bubbleLevel
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = view
    }

    public func show(text: String, anchoredTo mascotFrame: CGRect) {
        label.stringValue = text
        let size = CGSize(width: max(100, min(260, CGFloat(text.count * 8 + 32))), height: 42)
        let frame = CGRect(x: mascotFrame.midX - size.width / 2, y: mascotFrame.maxY + 10, width: size.width, height: size.height)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    public func hide() {
        window.orderOut(nil)
    }
}
