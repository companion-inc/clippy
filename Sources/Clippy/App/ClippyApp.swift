import AppKit
import ClippyCore

@main
@MainActor
final class ClippyApp: NSObject, NSApplicationDelegate {
    private static let characterScale: CGFloat = 2

    private var mascot: (any DesktopMascot)?
    private var pendingIdle: DispatchWorkItem?

    private var chatBubble: ClippyBubbleController?
    private var conversation: (any AgentBrain)?
    private var isTurnRunning = false
    private var commandTimer: Timer?
    private var dragTrackTimer: Timer?
    private var activeActivityState: AgentActivityState = .idle

    static func main() {
        let app = NSApplication.shared
        let delegate = ClippyApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        // run() only returns via NSApp.stop (terminate exits the process from
        // inside). Reaching here means something stopped the run loop.
        delegate.log("NSApplication.run returned unexpectedly; exiting")
    }

    func applicationWillTerminate(_ notification: Notification) {
        log("applicationWillTerminate")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startMascot(Self.makeMascot())
        setUpBrain()
        startCommandChannel()
        startDragTracking()
    }

    // MARK: - Mascot setup

    private static func makeMascot() -> any DesktopMascot {
        do {
            return try ClippyMascot(packRoot: clippyResourceRoot(), scale: characterScale)
        } catch {
            fatalError("Clippy resources failed to load: \(error)")
        }
    }

    private func startMascot(_ mascot: any DesktopMascot) {
        let bubble = ClippyBubbleController(theme: mascot.theme)

        self.mascot = mascot
        self.chatBubble = bubble

        bubble.setAnchor(mascot.frame)
        bubble.configure { [weak self] text in
            self?.sendMessage(text)
        }
        mascot.windowController.contextMenuProvider = { [weak self] in
            self?.makeContextMenu()
        }
        mascot.windowController.onCharacterClick = { [weak self] in
            self?.toggleChat()
        }
        mascot.show()
        mascot.play(mascot.theme.greetingAnimationName) { [weak self] _, _ in
            self?.scheduleNextIdle()
        }
        bubble.showMessage(mascot.theme.greetingText, autoHide: 6)
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
        guard let mascot, !isTurnRunning else {
            return
        }
        let name = mascot.idleAnimationNames.randomElement() ?? "RestPose"
        mascot.play(name) { [weak self, weak mascot] _, endState in
            switch endState {
            case .waiting:
                mascot?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    // MARK: - Brain

    private func setUpBrain() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let localCLI = LocalCLIConversation.locateBinary() {
            conversation = LocalCLIConversation(binaryPath: localCLI, workingDirectory: home)
            log("shared brain ready: \(localCLI)")
        } else {
            log("brain disabled: local CLI not found")
        }
    }

    private func toggleChat() {
        guard let mascot, let chatBubble else {
            return
        }
        chatBubble.setAnchor(mascot.frame)
        if chatBubble.isInputMode {
            chatBubble.hide()
            return
        }
        mascot.play(mascot.theme.openInputAnimationName) { [weak mascot] _, state in
            if state == .waiting {
                mascot?.exitCurrentAnimation()
            }
        }
        chatBubble.openInput()
    }

    private func sendMessage(_ text: String) {
        guard let chatBubble else {
            return
        }
        guard !isTurnRunning else {
            chatBubble.showReply("(One sec — still working on your last message.)")
            return
        }
        guard let conversation else {
            chatBubble.showReply("(My local brain isn't installed.)")
            return
        }
        isTurnRunning = true
        pendingIdle?.cancel()
        chatBubble.recordUserLine(text)
        chatBubble.hide() // thinking is shown by the character, not text
        log("user: \(text)")
        playActivityState(.thinking)

        Task { [weak self] in
            let turn = await conversation.send(text)
            await MainActor.run {
                self?.receiveReply(turn)
            }
        }
    }

    private func receiveReply(_ turn: AgentTurn) {
        isTurnRunning = false
        if let frame = mascot?.frame { chatBubble?.setAnchor(frame) }
        chatBubble?.showReply(turn.text)
        log("clippy: \(turn.text.prefix(120))")
        playActivityState(turn.isError ? .error : .attention)

        let animationName = turn.isError
            ? (mascot?.theme.errorAnimationName ?? "Alert")
            : (mascot?.theme.replyAnimationName ?? "Explain")
        mascot?.play(animationName) { [weak self, weak mascot] _, state in
            switch state {
            case .waiting:
                mascot?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    private func playActivityState(_ state: AgentActivityState) {
        activeActivityState = state
        pendingIdle?.cancel()
        guard state != .idle else {
            scheduleNextIdle()
            return
        }
        guard let binding = mascot?.theme.animation(for: state) else {
            scheduleNextIdle()
            return
        }
        if binding.repeatsUntilStateChange {
            playLooping(binding.animationName, while: state)
        } else {
            playTransient(binding.animationName)
        }
    }

    private func playTransient(_ name: String) {
        mascot?.play(name) { [weak self, weak mascot] _, state in
            switch state {
            case .waiting:
                mascot?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    /// Plays an animation and keeps replaying it while that activity state remains visible.
    private func playLooping(_ name: String, while activityState: AgentActivityState) {
        mascot?.play(name) { [weak self] _, endState in
            guard let self else {
                return
            }
            switch endState {
            case .waiting:
                self.mascot?.exitCurrentAnimation()
            case .exited:
                if self.activeActivityState == activityState {
                    self.playLooping(name, while: activityState)
                }
            }
        }
    }

    // MARK: - Keep the chat window glued to the mascot when dragged

    private func startDragTracking() {
        dragTrackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let frame = self.mascot?.frame else {
                    return
                }
                self.chatBubble?.setAnchor(frame)
            }
        }
    }

    // MARK: - Context menu (right-click on the character)

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let chat = NSMenuItem(
            title: mascot?.theme.chatMenuTitle ?? MascotTheme.clippy.chatMenuTitle,
            action: #selector(chatClicked),
            keyEquivalent: ""
        )
        chat.target = self
        menu.addItem(chat)

        let animate = NSMenuItem(title: "Animate!", action: #selector(animateNow), keyEquivalent: "")
        animate.target = self
        menu.addItem(animate)

        let mute = NSMenuItem(title: "Mute Sounds", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.state = (mascot?.isMuted ?? false) ? .on : .off
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
        guard let mascot else {
            return
        }
        let name = mascot.gestureAnimationNames.randomElement() ?? mascot.theme.fallbackGestureAnimationName
        mascot.play(name) { [weak self, weak mascot] _, endState in
            switch endState {
            case .waiting:
                mascot?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    @objc private func toggleMute() {
        mascot?.isMuted.toggle()
    }

    @objc private func quitClippy() {
        NSApp.terminate(nil)
    }

    // MARK: - Resources

    private static func clippyResourceRoot() -> URL {
        let fileRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/Characters/Clippy")
        let cwdRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Resources/Characters/Clippy")
        let bundleRoot = Bundle.main.resourceURL?.appending(path: "Characters/Clippy")
        let candidates = [bundleRoot, cwdRoot, fileRoot].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appending(path: "character.json").path) } ?? fileRoot
    }

    // MARK: - Debug instrumentation

    /// With CLIPPY_CMD_FILE set, polls a command file so the app can be driven
    /// headlessly: `ask:<text>`, `open`, `snapshot`, `move:`, `park:`, `state:`.
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
                if let frame = mascot?.frame { chatBubble?.setAnchor(frame) }
                chatBubble?.openInput()
            } else if command == "snapshot" {
                writeSnapshot(index: 99, directory: snapshotDirectory ?? "/tmp")
                writeChatSnapshot(directory: snapshotDirectory ?? "/tmp")
            } else if command.hasPrefix("move:") {
                moveMascot(command: String(command.dropFirst(5)))
            } else if command.hasPrefix("park:") {
                parkMascot(command: String(command.dropFirst(5)))
            } else if command.hasPrefix("state:") {
                applyStateCommand(String(command.dropFirst(6)))
            }
        }
    }

    private func applyStateCommand(_ command: String) {
        guard let state = AgentActivityState(rawValue: command.trimmingCharacters(in: .whitespaces)) else {
            return
        }
        log("state: \(state.rawValue)")
        playActivityState(state)
    }

    private func moveMascot(command: String) {
        let parts = command.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else {
            return
        }
        mascot?.move(to: CGPoint(x: parts[0], y: parts[1]), animated: true)
        if let frame = mascot?.frame { chatBubble?.setAnchor(frame) }
    }

    private func parkMascot(command: String) {
        guard
            let edge = MascotParkEdge(rawValue: command),
            let visibleFrame = NSScreen.main?.visibleFrame
        else {
            return
        }
        mascot?.park(in: visibleFrame, edge: edge)
        if let frame = mascot?.frame { chatBubble?.setAnchor(frame) }
    }

    private var snapshotDirectory: String? {
        ProcessInfo.processInfo.environment["CLIPPY_SNAPSHOT_DIR"]
    }

    func log(_ message: String) {
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
        guard let data = mascot?.snapshotPNGData() else {
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
