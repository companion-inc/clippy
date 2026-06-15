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
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = pill
    }

    /// Show the pill and keep it pinned beside the System Settings window. Follows it
    /// (a 0.4s timer) so it stays put even if the user moves Settings around.
    public func show(autoHideAfter seconds: TimeInterval = 90) {
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

    /// Pin to the left of System Settings (where it won't cover the list), vertically
    /// near the top where the Accessibility/Screen Recording list lives. Falls back to
    /// the top-center of the screen until System Settings appears.
    private func reposition() {
        let size = window.frame.size
        if let settings = Self.systemSettingsFrame() {
            var x = settings.minX - size.width - 18
            // If there's no room on the left, sit to the right of Settings instead.
            if x < (NSScreen.main?.visibleFrame.minX ?? 0) + 8 {
                x = settings.maxX + 18
            }
            let y = settings.maxY - size.height - 64 // align near the top, by the list
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let vf = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 48))
        }
    }

    /// The System Settings (or legacy System Preferences) window in global AppKit
    /// coordinates. Window bounds + owner don't require Screen Recording permission.
    static func systemSettingsFrame() -> CGRect? {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        for window in list {
            let owner = (window[kCGWindowOwnerName as String] as? String) ?? ""
            guard owner == "System Settings" || owner == "System Preferences",
                  let bounds = window[kCGWindowBounds as String] as? [String: Any] else { continue }
            let x = bounds["X"] as? CGFloat ?? 0
            let y = bounds["Y"] as? CGFloat ?? 0
            let w = bounds["Width"] as? CGFloat ?? 0
            let h = bounds["Height"] as? CGFloat ?? 0
            guard w > 200, h > 200 else { continue } // skip menubar/popover slivers
            // CG (top-left origin, y-down) -> AppKit global (bottom-left origin, y-up).
            return CGRect(x: x, y: primaryHeight - y - h, width: w, height: h)
        }
        return nil
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
