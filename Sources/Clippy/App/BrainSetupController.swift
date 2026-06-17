import AppKit
import ClippyCore

@MainActor
final class BrainSetupController: NSWindowController {
    struct Actions {
        let selectModel: (String) -> Void
        let openVoiceKeys: () -> Void
        let openAccessibility: () -> Void
        let openScreenRecording: () -> Void
        let openMicrophone: () -> Void
        let finish: () -> Void
    }

    private let setupPanel: BrainSetupPanel

    init(selectedModelID: String, actions: Actions) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 492),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Clippy Setup"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.center()
        let panel = BrainSetupPanel(selectedModelID: selectedModelID, actions: actions)
        self.setupPanel = panel
        super.init(window: window)
        window.contentView = panel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        setupPanel.refresh()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        setupPanel.refresh()
    }
}

private final class BrainSetupPanel: NSView {
    private let actions: BrainSetupController.Actions
    private var selectedModelID: String

    private let codexStatus = NSTextField(labelWithString: "")
    private let codexPath = NSTextField(labelWithString: "")
    private let claudeStatus = NSTextField(labelWithString: "")
    private let claudePath = NSTextField(labelWithString: "")
    private let voiceStatus = NSTextField(labelWithString: "")
    private let permissionStatus = NSTextField(labelWithString: "")

    private let useCodexButton = RetroButton(title: "Use Codex")
    private let codexLoginButton = RetroButton(title: "Sign In")
    private let codexInstallButton = RetroButton(title: "Install")
    private let useClaudeButton = RetroButton(title: "Use Claude")
    private let claudePlanLoginButton = RetroButton(title: "Plan Login")
    private let claudeConsoleLoginButton = RetroButton(title: "Console")
    private let claudeInstallButton = RetroButton(title: "Install")

    init(selectedModelID: String, actions: BrainSetupController.Actions) {
        self.selectedModelID = selectedModelID
        self.actions = actions
        super.init(frame: NSRect(x: 0, y: 0, width: 620, height: 492))
        build()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        RetroPalette.face.setFill()
        bounds.fill()
        RetroBezel.draw(.window, in: bounds)
    }

    func refresh() {
        let codex = BrainDiscovery.codexStatus()
        let claude = BrainDiscovery.claudeStatus()

        codexStatus.stringValue = codex.statusText
        codexPath.stringValue = codex.binaryPath ?? "Install Codex CLI, then sign in with ChatGPT."
        useCodexButton.title = selectedModelID == ClippyModel.gpt55.id ? "Using" : "Use Codex"
        useCodexButton.isEnabledButton = codex.signedIn
        codexLoginButton.isEnabledButton = codex.isInstalled
        codexInstallButton.title = codex.isInstalled ? "Update" : "Install"

        claudeStatus.stringValue = claude.statusText
        claudePath.stringValue = claude.binaryPath ?? "Install Claude Code, then sign in with Claude."
        useClaudeButton.title = selectedModelID == ClippyModel.opus48.id ? "Using" : "Use Claude"
        useClaudeButton.isEnabledButton = claude.signedIn
        claudePlanLoginButton.isEnabledButton = claude.isInstalled
        claudeConsoleLoginButton.isEnabledButton = claude.isInstalled
        claudeInstallButton.title = claude.isInstalled ? "Update" : "Install"

        let missingProviders = ClippySecrets.missingRequiredProviderNames
        voiceStatus.stringValue = missingProviders.isEmpty
            ? "Ready"
            : "Missing " + missingProviders.joined(separator: " and ")

        let permissions = [
            ("Accessibility", AccessibilityPermission.isTrusted),
            ("Screen Recording", ScreenPerception.hasPermission),
            ("Microphone", MicrophonePermission.isGranted),
        ]
        let missingPermissions = permissions.filter { !$0.1 }.map(\.0)
        permissionStatus.stringValue = missingPermissions.isEmpty
            ? "Ready"
            : "Missing " + missingPermissions.joined(separator: ", ")

        needsDisplay = true
    }

    private func build() {
        addSubview(SetupTitleBar(title: "Clippy - Setup"))
        addSubview(label("Choose what Clippy should use", x: 24, y: 47, width: 260, height: 20, size: 14, bold: true))
        let copy = label(
            "Clippy can use Codex for screen control and Claude Code for local chat. Set up either one, or both.",
            x: 24,
            y: 71,
            width: 560,
            height: 18
        )
        copy.textColor = RetroPalette.grayText
        addSubview(copy)

        addBrainBox(
            title: "Codex / ChatGPT",
            status: codexStatus,
            path: codexPath,
            y: 104,
            primary: useCodexButton,
            login: codexLoginButton,
            secondaryLogin: nil,
            install: codexInstallButton
        )
        codexLoginButton.onClick = { Self.runInTerminal(title: "Codex Login", command: "codex login") }
        codexInstallButton.onClick = {
            Self.runInTerminal(
                title: "Install Codex",
                command: """
                if ! command -v npm >/dev/null 2>&1; then
                  echo "npm is required to install Codex CLI."
                  exit 1
                fi
                npm install -g @openai/codex
                codex login
                """
            )
        }
        useCodexButton.onClick = { [weak self] in
            self?.selectedModelID = ClippyModel.gpt55.id
            self?.actions.selectModel(ClippyModel.gpt55.id)
            self?.refresh()
        }

        addBrainBox(
            title: "Claude Code",
            status: claudeStatus,
            path: claudePath,
            y: 205,
            primary: useClaudeButton,
            login: claudePlanLoginButton,
            secondaryLogin: claudeConsoleLoginButton,
            install: claudeInstallButton
        )
        claudePlanLoginButton.onClick = {
            Self.runInTerminal(title: "Claude Plan Login", command: "claude auth login --claudeai")
        }
        claudeConsoleLoginButton.onClick = {
            Self.runInTerminal(title: "Claude API Login", command: "claude auth login --console")
        }
        claudeInstallButton.onClick = {
            Self.runInTerminal(
                title: "Install Claude Code",
                command: """
                if ! command -v npm >/dev/null 2>&1; then
                  echo "npm is required to install Claude Code."
                  exit 1
                fi
                npm install -g @anthropic-ai/claude-code
                claude auth login --claudeai
                """
            )
        }
        useClaudeButton.onClick = { [weak self] in
            self?.selectedModelID = ClippyModel.opus48.id
            self?.actions.selectModel(ClippyModel.opus48.id)
            self?.refresh()
        }

        addSetupRow(
            title: "Voice",
            detail: "Deepgram listens. xAI speaks.",
            status: voiceStatus,
            y: 313,
            buttons: [("Configure Keys", 112, { [weak self] in
                self?.actions.openVoiceKeys()
            })]
        )

        addSetupRow(
            title: "Mac Permissions",
            detail: "Accessibility, Screen Recording, and Microphone.",
            status: permissionStatus,
            y: 368,
            buttons: [
                ("Access", 66, { [weak self] in self?.actions.openAccessibility() }),
                ("Screen", 66, { [weak self] in self?.actions.openScreenRecording() }),
                ("Mic", 50, { [weak self] in self?.actions.openMicrophone() }),
            ]
        )

        let refreshButton = RetroButton(title: "Refresh")
        refreshButton.frame = NSRect(x: 360, y: 445, width: 78, height: 23)
        refreshButton.onClick = { [weak self] in self?.refresh() }
        addSubview(refreshButton)

        let doneButton = RetroButton(title: "Done")
        doneButton.isDefault = true
        doneButton.frame = NSRect(x: 452, y: 445, width: 66, height: 23)
        doneButton.onClick = { [weak self] in
            self?.actions.finish()
            self?.window?.close()
        }
        addSubview(doneButton)

        let laterButton = RetroButton(title: "Later")
        laterButton.frame = NSRect(x: 530, y: 445, width: 66, height: 23)
        laterButton.onClick = { [weak self] in
            self?.actions.finish()
            self?.window?.close()
        }
        addSubview(laterButton)
    }

    private func addBrainBox(
        title: String,
        status: NSTextField,
        path: NSTextField,
        y: CGFloat,
        primary: RetroButton,
        login: RetroButton,
        secondaryLogin: RetroButton?,
        install: RetroButton
    ) {
        let box = RetroPanel(frame: NSRect(x: 24, y: y, width: 572, height: 86))
        box.bezel = .field
        addSubview(box)

        addSubview(label(title, x: 38, y: y + 12, width: 170, height: 18, bold: true))
        configureStatusLabel(status)
        status.frame = NSRect(x: 212, y: y + 12, width: 150, height: 18)
        addSubview(status)

        configurePathLabel(path)
        path.frame = NSRect(x: 38, y: y + 36, width: 330, height: 18)
        addSubview(path)

        primary.frame = NSRect(x: 382, y: y + 13, width: 86, height: 23)
        addSubview(primary)
        login.frame = NSRect(x: 478, y: y + 13, width: 86, height: 23)
        addSubview(login)

        if let secondaryLogin {
            secondaryLogin.frame = NSRect(x: 382, y: y + 49, width: 86, height: 23)
            addSubview(secondaryLogin)
            install.frame = NSRect(x: 478, y: y + 49, width: 86, height: 23)
        } else {
            install.frame = NSRect(x: 478, y: y + 49, width: 86, height: 23)
        }
        addSubview(install)
    }

    private func addSetupRow(
        title: String,
        detail: String,
        status: NSTextField,
        y: CGFloat,
        buttons: [(String, CGFloat, () -> Void)]
    ) {
        let box = RetroPanel(frame: NSRect(x: 24, y: y, width: 572, height: 45))
        box.bezel = .field
        addSubview(box)
        addSubview(label(title, x: 38, y: y + 8, width: 128, height: 18, bold: true))
        let detailLabel = label(detail, x: 38, y: y + 25, width: 300, height: 14, size: 10)
        detailLabel.textColor = RetroPalette.grayText
        addSubview(detailLabel)

        configureStatusLabel(status)
        status.frame = NSRect(x: 226, y: y + 14, width: 150, height: 18)
        addSubview(status)

        var x: CGFloat = 386
        for (title, width, action) in buttons {
            let button = RetroButton(title: title)
            button.frame = NSRect(x: x, y: y + 11, width: width, height: 23)
            button.onClick = action
            addSubview(button)
            x += width + 8
        }
    }

    private func configureStatusLabel(_ field: NSTextField) {
        field.font = RetroFont.ui(11, bold: true)
        field.textColor = RetroPalette.text
    }

    private func configurePathLabel(_ field: NSTextField) {
        field.font = RetroFont.ui(10)
        field.textColor = RetroPalette.grayText
        field.lineBreakMode = .byTruncatingMiddle
    }

    private func label(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        size: CGFloat = 11,
        bold: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = RetroFont.ui(size, bold: bold)
        field.textColor = RetroPalette.text
        field.frame = NSRect(x: x, y: y, width: width, height: height)
        return field
    }

    private static func runInTerminal(title: String, command: String) {
        do {
            let directory = try setupScriptDirectory()
            let slug = title
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")
            let scriptURL = directory.appendingPathComponent("\(slug)-\(Int(Date().timeIntervalSince1970)).command")
            let script = """
            #!/bin/zsh
            clear
            echo "Clippy setup: \(title)"
            echo
            (
            \(command)
            )
            status=$?
            echo
            if [ $status -eq 0 ]; then
              echo "Done. Return to Clippy and press Refresh."
            else
              echo "Setup exited with status $status."
            fi
            echo
            read -k 1 "?Press any key to close this window..."
            exit $status
            """
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: scriptURL.path
            )
            NSWorkspace.shared.open(scriptURL)
        } catch {
            NSSound.beep()
        }
    }

    private static func setupScriptDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base
            .appendingPathComponent("Clippy", isDirectory: true)
            .appendingPathComponent("Setup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class SetupTitleBar: NSView {
    private let title: String

    init(title: String) {
        self.title = title
        super.init(frame: NSRect(x: 3, y: 3, width: 614, height: 22))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [RetroPalette.titleBar, RetroPalette.titleBarGradientEnd])?
            .draw(in: bounds, angle: 0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(12, bold: true),
            .foregroundColor: RetroPalette.captionText,
        ]
        (title as NSString).draw(at: NSPoint(x: 6, y: 4), withAttributes: attrs)
    }
}
