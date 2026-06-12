import AppKit
import ClippyCore

@main
@MainActor
final class ClippyApp: NSObject, NSApplicationDelegate {
    private static let characterScale: CGFloat = 2
    private static let idleAnimations = [
        "Idle1_1", "IdleAtom", "IdleEyeBrowRaise", "IdleFingerTap",
        "IdleHeadScratch", "IdleRopePile", "IdleSideToSide", "IdleSnooze",
        "LookLeft", "LookRight", "Thinking", "Searching",
    ]
    private static let gestureAnimations = [
        "Congratulate", "GetAttention", "Wave", "Print", "Save", "GetArtsy",
        "GetTechy", "GetWizardy", "Explain", "Alert", "CheckingSomething",
        "EmptyTrash", "SendMail", "Writing", "Processing",
    ]

    private var mascotWindow: MascotWindowController?
    private var bubbleWindow: BubbleWindowController?
    private var morphRenderer: CoreAnimationMorphRenderer?
    private var rasterRenderer: SpriteKitRasterCharacterRenderer?
    private var animator: ClippitAnimator?
    private var soundBank: ClippitSoundBank?
    private var pendingIdle: DispatchWorkItem?

    private var askInput: AskInputController?
    private var approvalPanel: ApprovalPanelController?
    private var assistantLoop: AssistantLoop?
    private var isTurnRunning = false
    private var pendingApproval: CheckedContinuation<Bool, Never>?
    private var commandTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = ClippyApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The classic Win97 Clippit sprite pack is the default look; the
        // experimental vector mascot stays behind CLIPPY_RENDERER=vector.
        if ProcessInfo.processInfo.environment["CLIPPY_RENDERER"] != "vector",
           let sheet = try? ClippitSpriteSheet(packRoot: Self.clippitResourceRoot()) {
            startClippit(with: sheet)
        } else {
            startMorphMascot()
        }
        setUpAssistant()
        startCommandChannel()
    }

    // MARK: - Clippit raster character

    private func startClippit(with sheet: ClippitSpriteSheet) {
        let size = CGSize(
            width: sheet.frameSize.width * Self.characterScale,
            height: sheet.frameSize.height * Self.characterScale
        )
        let renderer = SpriteKitRasterCharacterRenderer(size: size)
        let animator = ClippitAnimator(sheet: sheet, renderer: renderer)
        let mascotWindow = MascotWindowController(rendererView: renderer.view, size: size) { point in
            CGRect(origin: .zero, size: size).contains(point)
        }
        let bubbleWindow = BubbleWindowController()
        let soundBank = try? ClippitSoundBank(packRoot: Self.clippitResourceRoot())
        animator.soundBank = soundBank

        self.rasterRenderer = renderer
        self.animator = animator
        self.soundBank = soundBank
        self.mascotWindow = mascotWindow
        self.bubbleWindow = bubbleWindow
        self.askInput = AskInputController()
        self.approvalPanel = ApprovalPanelController()

        mascotWindow.contextMenuProvider = { [weak self] in
            self?.makeContextMenu()
        }
        mascotWindow.onCharacterClick = { [weak self] in
            self?.openAskInput()
        }
        mascotWindow.show()
        animator.play("Greeting") { [weak self] _, _ in
            self?.scheduleNextIdle()
        }
        bubbleWindow.show(
            text: "It looks like you're using a Mac. Would you like help?",
            anchoredTo: mascotWindow.frame,
            hideAfter: 6,
            attachedTo: mascotWindow.window
        )
        scheduleDebugSnapshots()
    }

    private func scheduleNextIdle() {
        pendingIdle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.playRandomIdle()
        }
        pendingIdle = work
        let delay = TimeInterval.random(in: 2...6)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func playRandomIdle() {
        guard let animator, !isTurnRunning else {
            return
        }
        let name = Self.idleAnimations.randomElement() ?? "RestPose"
        animator.play(name) { [weak self] _, endState in
            switch endState {
            case .waiting:
                animator.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    // MARK: - Assistant brain

    private func setUpAssistant() {
        guard let apiKey = Self.loadAnthropicKey() else {
            log("assistant disabled: no Anthropic API key found")
            return
        }
        let system = """
        You are Clippy, the classic paperclip assistant, now living on the user's macOS desktop. \
        You can really act on this Mac through your tools. Prefer answering directly when no \
        action is needed. Your replies appear in a small speech bubble, so keep them to one or \
        two short sentences. Never use markdown.
        """
        let tools: [AnthropicModelClient.ToolSpec] = [
            .init(
                name: "shell.exec",
                description: "Run a zsh command on the user's Mac and get its output. Requires user approval. Use for reading files, checking system state, opening apps (open -a), and other local actions.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "command": ["type": "string", "description": "The zsh command to run"],
                    ],
                    "required": ["command"],
                ]
            ),
        ]
        let makeClient: @Sendable () -> AnthropicModelClient = {
            AnthropicModelClient(apiKey: apiKey, system: system, tools: tools)
        }
        self.makeModelClient = makeClient
        let router = ToolRouter()
        self.toolRouter = router
        Task {
            await router.register(name: "shell.exec", executor: ShellToolExecutor())
        }
    }

    private var makeModelClient: (@Sendable () -> AnthropicModelClient)?
    private var toolRouter: ToolRouter?

    private func openAskInput() {
        guard let mascotWindow, let askInput, !isTurnRunning else {
            return
        }
        animator?.play("GetAttention") { [weak self] _, state in
            if state == .waiting {
                self?.animator?.exitCurrentAnimation()
            }
        }
        askInput.show(
            anchoredTo: mascotWindow.frame,
            onSubmit: { [weak self] text in
                self?.runTurn(text)
            },
            onCancel: { [weak self] in
                self?.scheduleNextIdle()
            }
        )
    }

    private func runTurn(_ text: String) {
        guard let makeModelClient, let toolRouter, !isTurnRunning else {
            bubbleShow("I can't think right now — no API key configured.", hideAfter: 6)
            return
        }
        isTurnRunning = true
        pendingIdle?.cancel()
        bubbleWindow?.hide()
        log("turn start: \(text)")
        playLooping("Thinking")

        // Fresh client per turn: each turn is its own conversation.
        let loop = AssistantLoop(modelClient: makeModelClient(), toolRouter: toolRouter)
        self.assistantLoop = loop

        let hooks = AssistantLoop.Hooks(
            approvalHandler: { [weak self] request in
                await self?.requestApproval(request) ?? false
            },
            onToolStarted: { [weak self] name in
                Task { @MainActor in
                    self?.log("tool start: \(name)")
                    self?.playLooping("Processing")
                }
            },
            onToolFinished: { [weak self] name, status in
                Task { @MainActor in
                    self?.log("tool done: \(name) -> \(status.rawValue)")
                    self?.playLooping("Thinking")
                }
            }
        )

        Task { [weak self] in
            let result = await loop.run(userText: text, hooks: hooks)
            await MainActor.run {
                self?.finishTurn(result)
            }
        }
    }

    private func requestApproval(_ request: ApprovalRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor [weak self] in
                guard let self, let mascotWindow, let approvalPanel else {
                    continuation.resume(returning: false)
                    return
                }
                self.log("approval requested: \(request.invocation.name) — \(request.reason)")
                self.pendingApproval = continuation
                self.playLooping("IdleEyeBrowRaise")
                approvalPanel.show(request: request, anchoredTo: mascotWindow.frame) { [weak self] approved in
                    self?.log("approval resolved: \(approved ? "approved" : "denied")")
                    self?.pendingApproval = nil
                    continuation.resume(returning: approved)
                }
            }
        }
    }

    private func finishTurn(_ result: AssistantLoopResult) {
        isTurnRunning = false
        assistantLoop = nil
        let usedTools = !result.toolResults.isEmpty
        let answer: String
        switch result.stopReason {
        case .final, .modelError:
            answer = result.finalText ?? "Hmm, I came up empty."
        case .maxRounds:
            answer = "That took too many steps — let's try something smaller."
        case .approvalRequired:
            answer = "I'd need your approval for that one."
        }
        log("turn done (\(result.stopReason.rawValue)): \(answer)")
        animator?.play(usedTools ? "Congratulate" : "Explain") { [weak self] _, state in
            switch state {
            case .waiting:
                self?.animator?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
        bubbleShow(answer, hideAfter: 14)
    }

    /// Plays an animation and keeps replaying it until something else starts.
    private func playLooping(_ name: String) {
        animator?.play(name) { [weak self] played, state in
            guard let self else {
                return
            }
            switch state {
            case .waiting:
                self.animator?.exitCurrentAnimation()
            case .exited:
                if self.isTurnRunning, self.animator?.currentAnimationName == played {
                    self.playLooping(name)
                }
            }
        }
    }

    private func bubbleShow(_ text: String, hideAfter: TimeInterval?) {
        guard let mascotWindow, let bubbleWindow else {
            return
        }
        bubbleWindow.show(
            text: text,
            anchoredTo: mascotWindow.frame,
            hideAfter: hideAfter,
            attachedTo: mascotWindow.window
        )
    }

    private static func loadAnthropicKey() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let key = environment["ANTHROPIC_API_KEY"], key.hasPrefix("sk-ant-"), !key.hasPrefix("sk-ant-oat") {
            return key
        }
        // Local fallback: shared key file used by sibling Companion projects.
        let envFile = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "companion-android/.env")
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else {
            return nil
        }
        for line in contents.split(separator: "\n") {
            if line.hasPrefix("ANTHROPIC_API_KEY=") {
                return String(line.dropFirst("ANTHROPIC_API_KEY=".count))
            }
        }
        return nil
    }

    // MARK: - Context menu (right-click on the character)

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let ask = NSMenuItem(title: "Ask Clippy…", action: #selector(askClicked), keyEquivalent: "")
        ask.target = self
        menu.addItem(ask)

        let animate = NSMenuItem(title: "Animate!", action: #selector(animateNow), keyEquivalent: "")
        animate.target = self
        menu.addItem(animate)

        let mute = NSMenuItem(title: "Mute Sounds", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.state = (soundBank?.isMuted ?? false) ? .on : .off
        menu.addItem(mute)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Clippy", action: #selector(quitClippy), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func askClicked() {
        openAskInput()
    }

    @objc private func animateNow() {
        pendingIdle?.cancel()
        guard let animator else {
            return
        }
        let name = Self.gestureAnimations.randomElement() ?? "Wave"
        animator.play(name) { [weak self] _, endState in
            switch endState {
            case .waiting:
                animator.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    @objc private func toggleMute() {
        soundBank?.isMuted.toggle()
    }

    @objc private func quitClippy() {
        NSApp.terminate(nil)
    }

    // MARK: - Resources

    private static func clippitResourceRoot() -> URL {
        let fileRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/Characters/Clippit")
        let cwdRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Resources/Characters/Clippit")
        let bundleRoot = Bundle.main.resourceURL?.appending(path: "Characters/Clippit")
        let candidates = [bundleRoot, cwdRoot, fileRoot].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appending(path: "character.json").path) } ?? fileRoot
    }

    // MARK: - Morph mascot (experimental vector path)

    private func startMorphMascot() {
        let renderer = CoreAnimationMorphRenderer()
        let mascotWindow = MascotWindowController(
            rendererLayer: renderer.rootLayer,
            size: renderer.bounds.size
        ) { point in
            renderer.containsVisiblePoint(point)
        }
        let bubbleWindow = BubbleWindowController()

        self.morphRenderer = renderer
        self.mascotWindow = mascotWindow
        self.bubbleWindow = bubbleWindow
        self.askInput = AskInputController()
        self.approvalPanel = ApprovalPanelController()

        mascotWindow.show()
        renderer.appear()
        renderer.startIdleBehaviors()
        bubbleWindow.show(
            text: "Hi! Need help with anything?",
            anchoredTo: mascotWindow.frame,
            hideAfter: 5,
            attachedTo: mascotWindow.window
        )
    }

    // MARK: - Debug instrumentation

    /// With CLIPPY_CMD_FILE set, polls a command file so the app can be driven
    /// headlessly: `ask:<text>`, `approve`, `deny`, `snapshot`.
    private func startCommandChannel() {
        guard let path = ProcessInfo.processInfo.environment["CLIPPY_CMD_FILE"] else {
            return
        }
        FileManager.default.createFile(atPath: path, contents: Data())
        commandTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.drainCommands(at: path)
            }
        }
    }

    private func drainCommands(at path: String) {
        guard
            let data = FileManager.default.contents(atPath: path),
            !data.isEmpty,
            let text = String(data: data, encoding: .utf8)
        else {
            return
        }
        try? Data().write(to: URL(fileURLWithPath: path))
        for line in text.split(separator: "\n") {
            let command = line.trimmingCharacters(in: .whitespaces)
            if command.hasPrefix("ask:") {
                runTurn(String(command.dropFirst(4)))
            } else if command == "approve" {
                approvalPanel?.hide()
                pendingApproval?.resume(returning: true)
                log("approval resolved: approved (via command channel)")
                pendingApproval = nil
            } else if command == "deny" {
                approvalPanel?.hide()
                pendingApproval?.resume(returning: false)
                log("approval resolved: denied (via command channel)")
                pendingApproval = nil
            } else if command == "snapshot" {
                writeSnapshot(index: 99, directory: snapshotDirectory ?? "/tmp")
                writeBubbleSnapshot(directory: snapshotDirectory ?? "/tmp")
            }
        }
    }

    private var snapshotDirectory: String? {
        ProcessInfo.processInfo.environment["CLIPPY_SNAPSHOT_DIR"]
    }

    private func log(_ message: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
        let url = URL(fileURLWithPath: snapshotDirectory ?? NSTemporaryDirectory())
            .appending(path: "transcript.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Debug aid: with CLIPPY_SNAPSHOT_DIR set, renders the live SpriteKit
    /// scene to PNG frames so the rendered look can be inspected headlessly.
    private func scheduleDebugSnapshots() {
        guard let dir = snapshotDirectory else {
            return
        }
        for index in 1...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.7) { [weak self] in
                self?.writeSnapshot(index: index, directory: dir)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.writeBubbleSnapshot(directory: dir)
        }
    }

    private func writeSnapshot(index: Int, directory: String) {
        guard
            let renderer = rasterRenderer,
            let scene = renderer.view.scene,
            let texture = renderer.view.texture(from: scene)
        else {
            return
        }
        let rep = NSBitmapImageRep(cgImage: texture.cgImage())
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return
        }
        let url = URL(fileURLWithPath: directory).appending(path: "frame-\(index).png")
        try? data.write(to: url)
    }

    private func writeBubbleSnapshot(directory: String) {
        guard
            let view = bubbleWindow?.window.contentView,
            bubbleWindow?.window.isVisible == true,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: directory).appending(path: "bubble.png"))
    }
}
