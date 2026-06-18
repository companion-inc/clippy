import AppKit

@MainActor
public final class ClippyOnboardingDemoController {
    public struct Target: Equatable, Sendable {
        public let center: CGPoint
        public let radius: CGFloat

        public init(center: CGPoint, radius: CGFloat) {
            self.center = center
            self.radius = radius
        }
    }

    private final class DemoWindow: NSWindow {
        var onEscape: (() -> Void)?

        override var canBecomeKey: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onEscape?()
                return
            }
            super.keyDown(with: event)
        }
    }

    private let window: DemoWindow
    private let panel: DemoPanel
    private let onBuild: (URL) -> Void
    private let onClose: () -> Void

    public init(onBuild: @escaping (URL) -> Void, onClose: @escaping () -> Void) {
        self.onBuild = onBuild
        self.onClose = onClose

        let frame = Self.initialFrame()
        let window = DemoWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = WindowLevelPolicy.bubbleLevel - 2
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let panel = DemoPanel(frame: CGRect(origin: .zero, size: frame.size))
        self.window = window
        self.panel = panel
        window.contentView = panel
        window.onEscape = { onClose() }
        panel.onClose = { onClose() }
        panel.onBuild = { [weak panel] in
            do {
                let url = try Self.createDemoPage()
                panel?.markBuilt(url: url)
                onBuild(url)
            } catch {
                panel?.showError()
            }
        }
    }

    public func show() {
        if window.isVisible == false {
            window.setFrame(Self.initialFrame(), display: false)
        }
        window.orderFrontRegardless()
    }

    public func hide() {
        window.orderOut(nil)
    }

    public var buildTarget: Target? {
        panel.buildTarget(in: window)
    }

    public var isVisible: Bool {
        window.isVisible
    }

    nonisolated public static func onboardingHTML() -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Clippy First Page</title>
          <style>
            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              background: #101418;
              color: #101418;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }
            main {
              width: min(760px, calc(100vw - 32px));
              background: #fff9c7;
              border: 3px solid #111;
              box-shadow: 10px 10px 0 #4e71b8;
              padding: 34px;
            }
            h1 { margin: 0 0 10px; font-size: 42px; }
            p { margin: 0; font-size: 18px; line-height: 1.4; }
            button {
              margin-top: 24px;
              padding: 12px 16px;
              border: 2px solid #111;
              background: #4e71b8;
              color: white;
              font-weight: 700;
            }
          </style>
        </head>
        <body>
          <main>
            <h1>Built with Clippy</h1>
            <p>This page was created during onboarding so Clippy can point, guide, and react on screen.</p>
            <button>Ready</button>
          </main>
        </body>
        </html>
        """
    }

    private static func initialFrame() -> CGRect {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let size = CGSize(width: min(640, screen.width - 80), height: 420)
        return CGRect(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2 + 46,
            width: size.width,
            height: size.height
        )
    }

    private static func createDemoPage() throws -> URL {
        let root = try onboardingPageRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "index.html")
        let html = onboardingHTML()
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func onboardingPageRoot() throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return support
            .appending(path: "Clippy", directoryHint: .isDirectory)
            .appending(path: "OnboardingFirstTask", directoryHint: .isDirectory)
    }
}

private final class DemoPanel: NSView {
    var onBuild: (() -> Void)?
    var onClose: (() -> Void)?

    private let instruction = NSTextField(wrappingLabelWithString: "Let me show you the loop. Click Build Page.")
    private let status = NSTextField(labelWithString: "Clean practice window.")
    private let preview = DemoPreviewView()
    private let buildButton = RetroButton(title: "Build Page")

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let titleBar = RetroTitleBar(title: "Clippy - First Task")
        titleBar.translatesAutoresizingMaskIntoConstraints = false

        let closeBox = RetroButton(title: "X")
        closeBox.translatesAutoresizingMaskIntoConstraints = false
        closeBox.onClick = { [weak self] in self?.onClose?() }

        instruction.font = RetroFont.ui(14, bold: true)
        instruction.textColor = RetroPalette.text
        instruction.isBordered = false
        instruction.drawsBackground = false
        instruction.translatesAutoresizingMaskIntoConstraints = false

        status.font = RetroFont.ui(11)
        status.textColor = RetroPalette.text
        status.isBordered = false
        status.drawsBackground = false
        status.translatesAutoresizingMaskIntoConstraints = false

        preview.translatesAutoresizingMaskIntoConstraints = false

        buildButton.isDefault = true
        buildButton.translatesAutoresizingMaskIntoConstraints = false
        buildButton.onClick = { [weak self] in
            self?.buildButton.isEnabledButton = false
            self?.status.stringValue = "Building a tiny local page..."
            self?.onBuild?()
        }

        addSubview(titleBar)
        addSubview(closeBox)
        addSubview(instruction)
        addSubview(status)
        addSubview(preview)
        addSubview(buildButton)

        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            titleBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            titleBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            titleBar.heightAnchor.constraint(equalToConstant: 20),

            closeBox.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -2),
            closeBox.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            closeBox.widthAnchor.constraint(equalToConstant: 18),
            closeBox.heightAnchor.constraint(equalToConstant: 16),

            instruction.topAnchor.constraint(equalTo: titleBar.bottomAnchor, constant: 16),
            instruction.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            instruction.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            status.topAnchor.constraint(equalTo: instruction.bottomAnchor, constant: 8),
            status.leadingAnchor.constraint(equalTo: instruction.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: instruction.trailingAnchor),

            preview.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 16),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            preview.bottomAnchor.constraint(equalTo: buildButton.topAnchor, constant: -18),

            buildButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            buildButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            buildButton.widthAnchor.constraint(equalToConstant: 116),
            buildButton.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        RetroPalette.face.setFill()
        bounds.fill()
        RetroBezel.draw(.window, in: bounds)
    }

    func markBuilt(url: URL) {
        preview.isBuilt = true
        status.stringValue = "Created \(url.lastPathComponent) in Clippy's local practice folder."
        buildButton.title = "Built"
        buildButton.isEnabledButton = false
    }

    func showError() {
        status.stringValue = "I hit a local file error. The pointing step still works."
        buildButton.title = "Error"
        buildButton.isEnabledButton = false
    }

    func buildTarget(in window: NSWindow) -> ClippyOnboardingDemoController.Target? {
        guard buildButton.window === window else { return nil }
        let buttonFrame = buildButton.convert(buildButton.bounds, to: nil)
        let screenFrame = window.convertToScreen(buttonFrame)
        return .init(
            center: CGPoint(x: screenFrame.midX, y: screenFrame.midY),
            radius: max(38, max(screenFrame.width, screenFrame.height) * 0.62)
        )
    }
}

private final class DemoPreviewView: NSView {
    var isBuilt = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        RetroPalette.fieldBackground.setFill()
        bounds.fill()
        RetroBezel.draw(.field, in: bounds)

        let content = bounds.insetBy(dx: 22, dy: 20)
        if isBuilt {
            drawBuiltPreview(in: content)
        } else {
            drawEmptyPreview(in: content)
        }
    }

    private func drawEmptyPreview(in rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(18, bold: true),
            .foregroundColor: RetroPalette.grayText,
        ]
        ("Waiting for first task" as NSString).draw(at: CGPoint(x: rect.minX, y: rect.midY - 12), withAttributes: attrs)
    }

    private func drawBuiltPreview(in rect: CGRect) {
        NSColor(srgbRed: 1.0, green: 0.98, blue: 0.74, alpha: 1).setFill()
        let card = rect.insetBy(dx: 38, dy: 22)
        card.fill()
        RetroPalette.frame.setStroke()
        let path = NSBezierPath(rect: card)
        path.lineWidth = 2
        path.stroke()

        let shadow = CGRect(x: card.maxX - 8, y: card.maxY - 8, width: 8, height: 8)
        NSColor(srgbRed: 0.31, green: 0.44, blue: 0.72, alpha: 1).setFill()
        shadow.fill()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(24, bold: true),
            .foregroundColor: RetroPalette.text,
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(12),
            .foregroundColor: RetroPalette.text,
        ]
        ("Built with Clippy" as NSString).draw(at: CGPoint(x: card.minX + 24, y: card.minY + 24), withAttributes: titleAttrs)
        ("A tiny page from the onboarding loop." as NSString).draw(at: CGPoint(x: card.minX + 24, y: card.minY + 62), withAttributes: bodyAttrs)

        let button = CGRect(x: card.minX + 24, y: card.maxY - 56, width: 84, height: 28)
        NSColor(srgbRed: 0.31, green: 0.44, blue: 0.72, alpha: 1).setFill()
        button.fill()
        RetroPalette.frame.setStroke()
        NSBezierPath(rect: button).stroke()
        let readyAttrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(12, bold: true),
            .foregroundColor: NSColor.white,
        ]
        ("Ready" as NSString).draw(at: CGPoint(x: button.minX + 19, y: button.minY + 7), withAttributes: readyAttrs)
    }
}
