import AppKit

/// A "drag me into the list" permission guide, copied from Clippy's
/// PermissionGuideAssistant: a pill of Clippy.app that **locks itself to the System
/// Settings window** and follows it, so the privacy list you're dragging into is
/// always right next to the pill. Dragging carries the `.app` file URL, which the
/// Accessibility / Screen Recording list accepts as an "add this app" drop.
@MainActor
public final class PermissionDragController {
    private let window: NSWindow
    private let pill: AppDragPill
    private var followTimer: Timer?
    private var hideWork: DispatchWorkItem?
    private var targetScreen: NSScreen?

    public init(appURL: URL, prompt: String) {
        pill = AppDragPill(appURL: appURL, prompt: prompt)
        let size = NSSize(width: 264, height: 96)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        // NOT movable-by-background: that would steal the mouse-drag and move the
        // window instead of starting the file drag into System Settings.
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = pill
    }

    /// Show the pill and keep it pinned beside the System Settings window. Follows it
    /// (a 0.4s timer) so it stays put even if the user moves Settings around.
    public func show(autoHideAfter seconds: TimeInterval = 90) {
        // Pin to the display under the cursor when triggered (like Codex's getDisplayNearestPoint).
        targetScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        reposition()
        window.orderFrontRegardless()
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.reposition()
        }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    public func hide() {
        followTimer?.invalidate(); followTimer = nil
        hideWork?.cancel(); hideWork = nil
        window.orderOut(nil)
    }

    /// Top-right of the target display's work area — copied from Codex's overlay
    /// placement (x = workArea right edge − width, y a margin below the top). A fixed,
    /// predictable spot, instead of chasing wherever System Settings happens to open.
    private func reposition() {
        guard let visible = (targetScreen ?? NSScreen.main)?.visibleFrame else { return }
        let size = window.frame.size
        let margin: CGFloat = 16
        window.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.maxY - size.height - margin
        ))
    }
}

/// The draggable view: Clippy's app icon, a one-line instruction, and a "→". Starting
/// a drag puts the `.app` file URL on the pasteboard so the privacy list accepts it.
final class AppDragPill: NSView, NSDraggingSource {
    private let appURL: URL

    init(appURL: URL, prompt: String) {
        self.appURL = appURL
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        let icon = NSImageView()
        icon.image = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: prompt)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        item.setDraggingFrame(bounds.insetBy(dx: bounds.width / 2 - 26, dy: bounds.height / 2 - 26), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
