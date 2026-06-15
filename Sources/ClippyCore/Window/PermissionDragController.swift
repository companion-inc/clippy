import AppKit

/// Permission onboarding modeled on **Codex's** actual design (read out of
/// `chronicle-setup-state-*.js`): a self-contained dialog — NOT a strip pinned under
/// System Settings — holding a draggable app-icon tile labeled "Drag {App} into
/// {Permission} settings" plus an "Open System Settings" button. Codex has no
/// window-tracking code at all; the user opens Settings from the button and drags the
/// app tile across into the list. Rendered here in Clippy's Win95 / Office-97 skin.
@MainActor
public final class PermissionDragController {
    private let window: NSWindow
    private var hideWork: DispatchWorkItem?

    /// Final on-screen frame of the dialog (diagnostics / tests).
    public var windowFrame: NSRect { window.frame }

    /// Render the dialog's view hierarchy straight to PNG (diagnostics / tests) — lets
    /// us see the exact pixels without depending on Spaces / fullscreen compositing.
    public func snapshotPNG() -> Data? {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    public init(appURL: URL, permissionName: String, settingsAnchor: String) {
        let panel = RetroPermissionPanel(appURL: appURL, permissionName: permissionName, settingsAnchor: settingsAnchor)
        let size = NSSize(width: 404, height: 248)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isOpaque = true
        window.backgroundColor = RetroPalette.face
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = panel
        panel.onClose = { [weak self] in self?.hide() }
    }

    public func show(autoHideAfter seconds: TimeInterval = 180) {
        recenter()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    public func hide() {
        hideWork?.cancel(); hideWork = nil
        window.orderOut(nil)
    }

    /// Centered on the active screen, nudged a touch above center like a real dialog.
    private func recenter() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let f = window.frame
        window.setFrameOrigin(NSPoint(
            x: screen.midX - f.width / 2,
            y: screen.midY - f.height / 2 + 70
        ))
    }
}

/// The dialog body: navy title bar + close box, a one-line instruction, the draggable
/// Clippy tile, and an "Open System Settings" default button.
final class RetroPermissionPanel: NSView {
    var onClose: (() -> Void)?
    private let settingsAnchor: String
    override var isFlipped: Bool { true }

    init(appURL: URL, permissionName: String, settingsAnchor: String) {
        self.settingsAnchor = settingsAnchor
        super.init(frame: .zero)

        // — title bar (navy gradient) with a Win95 close box —
        let titleBar = RetroTitleBar(title: "Clippy — \(permissionName) Access")
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        let closeBox = RetroButton(title: "✕")
        closeBox.translatesAutoresizingMaskIntoConstraints = false
        closeBox.onClick = { [weak self] in self?.onClose?() }

        // — instruction copy —
        let blurb = NSTextField(wrappingLabelWithString:
            "Add Clippy to the \(permissionName) list so it can do its job. "
            + "Drag the Clippy tile below into the list — or click Open System Settings and switch Clippy on.")
        blurb.font = RetroFont.ui(12)
        blurb.textColor = RetroPalette.text
        blurb.isBordered = false
        blurb.drawsBackground = false
        blurb.translatesAutoresizingMaskIntoConstraints = false

        // — the draggable app tile (the whole point) —
        let tile = RetroDragTile(appURL: appURL, label: "Drag Clippy into \(permissionName) settings")
        tile.translatesAutoresizingMaskIntoConstraints = false

        // — open-settings button —
        let openButton = RetroButton(title: "Open System Settings")
        openButton.isDefault = true
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.onClick = { [weak self] in self?.openSettings() }

        addSubview(titleBar)
        addSubview(closeBox)
        addSubview(blurb)
        addSubview(tile)
        addSubview(openButton)

        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            titleBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            titleBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            titleBar.heightAnchor.constraint(equalToConstant: 20),

            closeBox.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -2),
            closeBox.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            closeBox.widthAnchor.constraint(equalToConstant: 18),
            closeBox.heightAnchor.constraint(equalToConstant: 16),

            blurb.topAnchor.constraint(equalTo: titleBar.bottomAnchor, constant: 14),
            blurb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            blurb.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            tile.topAnchor.constraint(equalTo: blurb.bottomAnchor, constant: 14),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            tile.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            tile.heightAnchor.constraint(equalToConstant: 68),

            openButton.topAnchor.constraint(equalTo: tile.bottomAnchor, constant: 16),
            openButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            openButton.widthAnchor.constraint(equalToConstant: 168),
            openButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        RetroPalette.face.setFill()
        bounds.fill()
        RetroBezel.draw(.window, in: bounds) // raised dialog body
    }

    private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Win95 navy caption bar. Dragging it moves the whole dialog (so the icon tile keeps
/// its own drag gesture instead of the window stealing it).
final class RetroTitleBar: NSView {
    private let title: String
    override var isFlipped: Bool { true }

    init(title: String) { self.title = title; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [RetroPalette.titleBar, RetroPalette.titleBarGradientEnd])
        gradient?.draw(in: bounds, angle: 0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(12, bold: true),
            .foregroundColor: RetroPalette.captionText,
        ]
        (title as NSString).draw(at: NSPoint(x: 6, y: (bounds.height - 14) / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

/// The draggable Clippy tile: the app's own icon + label inside a raised chip, carrying
/// the .app file on drag (so it drops into the macOS permission list) with a grab cursor.
final class RetroDragTile: NSView, NSDraggingSource {
    private let appURL: URL
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(appURL: URL, label: String) {
        self.appURL = appURL
        super.init(frame: .zero)

        let icon = NSImageView()
        icon.image = Self.appIcon(for: appURL)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextField(labelWithString: label)
        text.font = RetroFont.ui(13, bold: true)
        text.textColor = RetroPalette.text
        text.isBordered = false
        text.drawsBackground = false
        text.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(text)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        RetroPalette.face.setFill()
        bounds.fill()
        RetroBezel.draw(.raised, in: bounds) // raised = "pick me up"
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand) // grab affordance, like Codex's cursor-grab
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.set()
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let icon = Self.appIcon(for: appURL)
        item.setDraggingFrame(CGRect(x: 12, y: bounds.midY - 22, width: 44, height: 44), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        NSCursor.arrow.set()
    }

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
}
