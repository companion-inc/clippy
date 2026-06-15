import AppKit

/// A floating "drag me" pill of Clippy.app that the user drags straight into a
/// System Settings privacy list (Accessibility / Screen Recording) — the way
/// Clippy onboards permissions. Dragging carries the `.app` file URL, which the
/// privacy list accepts as an "add this app" drop.
@MainActor
public final class PermissionDragController {
    private let window: NSWindow
    private let pill: AppDragPill
    private var hideWork: DispatchWorkItem?

    public init(appURL: URL, prompt: String) {
        pill = AppDragPill(appURL: appURL, prompt: prompt)
        let size = NSSize(width: 300, height: 104)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = pill
    }

    /// Show the pill near the top of the active screen, where System Settings opens,
    /// so the target list is right there to drag into. Auto-hides after `seconds`.
    public func show(autoHideAfter seconds: TimeInterval = 60) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 48))
        window.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    public func hide() {
        hideWork?.cancel()
        hideWork = nil
        window.orderOut(nil)
    }
}

/// The draggable view: Clippy's app icon + a one-line instruction. Starting a drag
/// puts the `.app` file URL on the pasteboard so the privacy list accepts the drop.
final class AppDragPill: NSView, NSDraggingSource {
    private let appURL: URL
    private let iconView = NSImageView()

    init(appURL: URL, prompt: String) {
        self.appURL = appURL
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        iconView.image = NSWorkspace.shared.icon(forFile: appURL.path)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: prompt)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(label)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        item.setDraggingFrame(iconView.frame, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
