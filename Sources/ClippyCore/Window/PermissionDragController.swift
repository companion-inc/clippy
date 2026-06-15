import AppKit

/// A "drag me into the list" permission guide, modeled on Clippy's
/// `PermissionGuideAssistant`: the strip **locks onto the System Settings window**
/// and stays attached while you drag the Clippy app into the privacy list.
///
/// Clippy's own copy: *"As soon as Settings opens, Clippy will attach the
/// guide automatically … the guide stays locked to System Settings."* So we don't
/// position once and hope — we poll until the Settings window is actually visible
/// on the active Space, attach the pill **centered directly underneath it**, and
/// keep following it. The pill stays hidden whenever Settings isn't in front, so it
/// never strands itself in a random corner (the old single-shot query did exactly
/// that when Settings opened a beat later or on another Space).
@MainActor
public final class PermissionDragController {
    private let window: NSWindow
    private let pill: RetroDragPill
    private var followTimer: Timer?
    private var hideWork: DispatchWorkItem?
    private var attached = false

    /// Final on-screen frame of the pill window (diagnostics / tests).
    public var windowFrame: NSRect { window.frame }

    public init(appURL: URL, prompt: String) {
        pill = RetroDragPill(appURL: appURL, prompt: prompt)
        let size = NSSize(width: 392, height: 88)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = false // don't steal the file-drag gesture
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = pill
    }

    public func show(autoHideAfter seconds: TimeInterval = 90) {
        attached = false
        // Poll for the Settings window and stay locked to it. Fast cadence so the
        // pill appears the instant Settings comes forward, then keeps tracking it.
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        track()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    public func hide() {
        followTimer?.invalidate(); followTimer = nil
        hideWork?.cancel(); hideWork = nil
        window.orderOut(nil)
        attached = false
    }

    /// Attach to / follow the System Settings window. While Settings isn't visible
    /// on the active Space, keep the pill hidden rather than guess a position.
    private func track() {
        guard let settings = Self.systemSettingsFrame() else {
            if attached { window.orderOut(nil); attached = false }
            return
        }
        window.setFrameOrigin(pillOrigin(under: settings))
        if !attached {
            window.orderFrontRegardless()
            attached = true
        }
    }

    /// Centered directly UNDERNEATH the Settings window, clamped to stay on the same
    /// display (so it never jumps onto a second monitor when Settings sits near an edge).
    private func pillOrigin(under settings: CGRect) -> NSPoint {
        let size = window.frame.size
        var x = settings.midX - size.width / 2
        var y = settings.minY - size.height - 12 // just below the bottom edge

        // Pick the display Settings actually lives on by its center point (deterministic
        // on multi-monitor setups; an intersection-area pick can flip to the wrong screen
        // on a transient frame and fling the pill into a corner).
        let center = CGPoint(x: settings.midX, y: settings.midY)
        let screen = (NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.main)?.visibleFrame ?? settings
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        y = min(max(y, screen.minY + 8), screen.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    /// The System Settings (or legacy System Preferences) window in global AppKit
    /// coordinates. Bounds + owner don't require Screen Recording permission. Uses
    /// `.optionOnScreenOnly` on purpose: we only attach when Settings is actually in
    /// front of the user, never to an off-Space/minimized window.
    public static func systemSettingsFrame() -> CGRect? {
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
            guard w > 200, h > 200 else { continue } // skip the tiny helper/menu windows
            return CGRect(x: x, y: primaryHeight - y - h, width: w, height: h)
        }
        return nil
    }
}

/// The draggable Clippy pill: the app's own icon + a one-line instruction, drawn in
/// the Win95 / Office-97 style (pale-yellow tooltip face, hard black frame + raised
/// bevel, MS Sans Serif). You drag the whole tile straight into the privacy list.
final class RetroDragPill: NSView, NSDraggingSource {
    private let appURL: URL
    override var isFlipped: Bool { true } // RetroBezel assumes a flipped coordinate space

    init(appURL: URL, prompt: String) {
        self.appURL = appURL
        super.init(frame: .zero)

        // Codex drags the app FILE using the app's OWN icon (app.getFileIcon). Mirror
        // that: load the bundle's real .icns directly so it's always Clippy's icon —
        // NSWorkspace.icon(forFile:) can serve a stale/generic tile for a freshly built
        // app LaunchServices hasn't indexed yet (that's how a placeholder slipped in).
        let icon = NSImageView()
        icon.image = Self.appIcon(for: appURL)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: prompt)
        label.font = RetroFont.ui(13)
        label.textColor = RetroPalette.text
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false

        // No arrow — Codex doesn't use one; you just drag the app tile into the list.
        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// The app's own icon, read straight from its bundle (CFBundleIconFile → .icns),
    /// falling back to LaunchServices. Matches Codex's `app.getFileIcon(appPath)`.
    private static func appIcon(for appURL: URL) -> NSImage {
        if let bundle = Bundle(url: appURL),
           let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            let base = iconName.hasSuffix(".icns") ? String(iconName.dropLast(5)) : iconName
            if let url = bundle.url(forResource: base, withExtension: "icns"),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    override func draw(_ dirtyRect: NSRect) {
        RetroPalette.infoBackground.setFill() // INFOBK pale yellow — the Office tooltip color
        bounds.fill()
        RetroBezel.draw(.raised, in: bounds)
        RetroPalette.frame.setStroke()
        let outline = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        item.setDraggingFrame(CGRect(x: 16, y: bounds.midY - 26, width: 52, height: 52), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
