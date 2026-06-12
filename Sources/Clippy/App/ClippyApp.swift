import AppKit
import ClippyCore

@main
@MainActor
final class ClippyApp: NSObject, NSApplicationDelegate {
    private static let characterScale: CGFloat = 2
    private static let idleAnimations = [
        "Idle1_1", "IdleAtom", "IdleEyeBrowRaise", "IdleFingerTap",
        "IdleHeadScratch", "IdleRopePile", "IdleSideToSide", "IdleSnooze",
        "LookLeft", "LookRight",
    ]
    private static let gestureAnimations = [
        "Congratulate", "GetAttention", "Wave", "Print", "Save", "GetArtsy",
        "GetTechy", "GetWizardy", "Explain", "Alert", "CheckingSomething",
        "EmptyTrash", "SendMail", "Writing", "Processing",
    ]

    private var mascotWindow: MascotWindowController?
    private var morphRenderer: CoreAnimationMorphRenderer?
    private var rasterRenderer: SpriteKitRasterCharacterRenderer?
    private var animator: ClippitAnimator?
    private var soundBank: ClippitSoundBank?
    private var pendingIdle: DispatchWorkItem?

    private var chatBubble: ClippyBubbleController?
    private var conversation: ClaudeCLIConversation?
    private var isTurnRunning = false
    private var commandTimer: Timer?
    private var dragTrackTimer: Timer?

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
        setUpBrain()
        startCommandChannel()
        startDragTracking()
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
        let soundBank = try? ClippitSoundBank(packRoot: Self.clippitResourceRoot())
        animator.soundBank = soundBank
        let bubble = ClippyBubbleController()

        self.rasterRenderer = renderer
        self.animator = animator
        self.soundBank = soundBank
        self.mascotWindow = mascotWindow
        self.chatBubble = bubble

        bubble.setAnchor(mascotWindow.frame)
        bubble.configure { [weak self] text in
            self?.sendMessage(text)
        }
        mascotWindow.contextMenuProvider = { [weak self] in
            self?.makeContextMenu()
        }
        mascotWindow.onCharacterClick = { [weak self] in
            self?.toggleChat()
        }
        mascotWindow.show()
        animator.play("Greeting") { [weak self] _, _ in
            self?.scheduleNextIdle()
        }
        bubble.showMessage("It looks like you're using a Mac. Click me to chat!", autoHide: 6)
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

    // MARK: - Brain: local Claude conversation

    private func setUpBrain() {
        guard let binary = ClaudeCLIConversation.locateBinary() else {
            log("brain disabled: local `claude` CLI not found")
            return
        }
        log("brain ready: \(binary)")
        self.conversation = ClaudeCLIConversation(
            binaryPath: binary,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    private func toggleChat() {
        guard let mascotWindow, let chatBubble else {
            return
        }
        chatBubble.setAnchor(mascotWindow.frame)
        if chatBubble.isInputMode {
            chatBubble.hide()
            return
        }
        animator?.play("GetAttention") { [weak self] _, state in
            if state == .waiting {
                self?.animator?.exitCurrentAnimation()
            }
        }
        chatBubble.openInput()
    }

    private func sendMessage(_ text: String) {
        guard let conversation, let chatBubble, !isTurnRunning else {
            chatBubble?.showReply("(My local Claude brain isn't installed.)")
            return
        }
        isTurnRunning = true
        pendingIdle?.cancel()
        chatBubble.showThinking(forUserLine: text)
        log("user: \(text)")
        playLooping("Thinking")

        Task { [weak self] in
            let turn = await conversation.send(text)
            await MainActor.run {
                self?.receiveReply(turn)
            }
        }
    }

    private func receiveReply(_ turn: ClaudeCLIConversation.Turn) {
        isTurnRunning = false
        chatBubble?.showReply(turn.text)
        log("clippy: \(turn.text.prefix(120))")

        animator?.play(turn.isError ? "Alert" : "Explain") { [weak self] _, state in
            switch state {
            case .waiting:
                self?.animator?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    /// Plays an animation and keeps replaying it until the turn ends.
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

    // MARK: - Keep the chat window glued to Clippy when dragged

    private func startDragTracking() {
        dragTrackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let frame = self.mascotWindow?.frame else {
                    return
                }
                self.chatBubble?.setAnchor(frame)
            }
        }
    }

    // MARK: - Context menu (right-click on the character)

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let chat = NSMenuItem(title: "Chat with Clippy…", action: #selector(chatClicked), keyEquivalent: "")
        chat.target = self
        menu.addItem(chat)

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

    @objc private func chatClicked() {
        toggleChat()
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
        let bubble = ClippyBubbleController()

        self.morphRenderer = renderer
        self.mascotWindow = mascotWindow
        self.chatBubble = bubble

        bubble.setAnchor(mascotWindow.frame)
        bubble.configure { [weak self] text in
            self?.sendMessage(text)
        }
        mascotWindow.onCharacterClick = { [weak self] in
            self?.toggleChat()
        }
        mascotWindow.show()
        renderer.appear()
        renderer.startIdleBehaviors()
        bubble.showMessage("Hi! Click me to chat.", autoHide: 5)
    }

    // MARK: - Debug instrumentation

    /// With CLIPPY_CMD_FILE set, polls a command file so the app can be driven
    /// headlessly: `ask:<text>`, `snapshot`.
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
                sendMessage(String(command.dropFirst(4)))
            } else if command == "open" {
                if let frame = mascotWindow?.frame { chatBubble?.setAnchor(frame) }
                chatBubble?.openInput()
            } else if command == "snapshot" {
                writeSnapshot(index: 99, directory: snapshotDirectory ?? "/tmp")
                writeChatSnapshot(directory: snapshotDirectory ?? "/tmp")
            } else if command == "expand" {
                chatBubble?.debugToggleExpanded()
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

    private func scheduleDebugSnapshots() {
        guard let dir = snapshotDirectory else {
            return
        }
        for index in 1...8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.7) { [weak self] in
                self?.writeSnapshot(index: index, directory: dir)
            }
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

    private func writeChatSnapshot(directory: String) {
        guard
            let view = chatBubble?.window.contentView,
            chatBubble?.isVisible == true,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: directory).appending(path: "chat.png"))
    }
}
