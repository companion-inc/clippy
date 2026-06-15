import AppKit
import ClippyCore

@main
@MainActor
final class ClippyApp: NSObject, NSApplicationDelegate {
    private static let characterScale: CGFloat = 2

    private var mascot: (any DesktopMascot)?
    private var pendingIdle: DispatchWorkItem?

    private var chatBubble: ClippyBubbleController?
    private var overlay: AnnotationOverlayWindow?
    private var ptt: PushToTalkMonitor?
    private var speech: SpeechCapture?
    private var deepgramSTT: DeepgramVoiceCapture?
    private var deepgramTTS: DeepgramTTS?
    private var usingDeepgram = false
    private var sttEnabled = UserDefaults.standard.object(forKey: "ClippySTTEnabled") as? Bool ?? true
    private var ttsEnabled = UserDefaults.standard.object(forKey: "ClippyTTSEnabled") as? Bool ?? true
    private var conversation: (any AgentBrain)?
    private var selectedModel: ClippyModel = {
        // Honor an explicit prior choice; otherwise detect which subscription
        // (Claude vs GPT) the user is signed into locally and default to that.
        if let id = UserDefaults.standard.string(forKey: "ClippySelectedModelID"),
           let saved = ClippyModel.by(id: id) {
            return saved
        }
        return BrainDiscovery.defaultModel()
    }()
    private var selectedVoice: ClippyVoice = {
        let id = UserDefaults.standard.string(forKey: "ClippyVoiceID")
        return id.flatMap(ClippyVoice.by(id:)) ?? .default
    }()
    private var isTurnRunning = false
    private var currentBrainTask: Task<Void, Never>?
    private var lastShot: ScreenPerception.Screenshot?
    private var overlayDismiss: DispatchWorkItem?
    private var commandTimer: Timer?
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
        RetroFont.registerBundledFonts()
        startMascot(Self.makeMascot())
        overlay = AnnotationOverlayWindow()
        setUpBrain()
        setUpVoice()
        startCommandChannel()
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
        bubble.setAnchorWindow(mascot.windowController.window)
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
        switch selectedModel.backend {
        case .claude:
            if let cli = LocalCLIConversation.locateBinary() {
                conversation = LocalCLIConversation(binaryPath: cli, workingDirectory: home, model: selectedModel.id)
                log("brain: claude \(selectedModel.id)")
            } else {
                conversation = nil
                log("brain disabled: claude CLI not found")
            }
        case .codex:
            if let cli = CodexConversation.locateBinary() {
                conversation = CodexConversation(binaryPath: cli, model: selectedModel.id, workingDirectory: home)
                log("brain: codex \(selectedModel.id)")
            } else {
                conversation = nil
                log("brain disabled: codex CLI not found")
            }
        }
    }

    // MARK: - Voice (hold Control+Option; Deepgram Nova-3 STT + Aura-2 TTS)

    private func setUpVoice() {
        deepgramSTT = DeepgramVoiceCapture()   // nil if no Deepgram key
        deepgramSTT?.onPartialTranscript = { [weak self] text in
            guard let self, !self.isTurnRunning else { return }
            if let frame = self.mascot?.frame { self.chatBubble?.setAnchor(frame) }
            self.chatBubble?.showReply(text)
        }
        deepgramTTS = DeepgramTTS(voiceModel: selectedVoice.id)
        if deepgramSTT == nil { speech = SpeechCapture() } // Apple on-device fallback
        log("voice: deepgram STT=\(deepgramSTT != nil) TTS=\(deepgramTTS != nil)")

        let monitor = PushToTalkMonitor(modifiers: [.control, .option])
        monitor.onBegin = { [weak self] in self?.beginVoiceTurn() }
        monitor.onEnd = { [weak self] in self?.endVoiceTurn() }
        self.ptt = monitor

        // Deepgram needs only the mic; the Apple fallback also needs Speech Recognition.
        let needsSpeechRecognition = (deepgramSTT == nil)
        Task { [weak self] in
            if needsSpeechRecognition {
                _ = await SpeechCapture.requestAuthorization()
            } else {
                _ = await SpeechCapture.requestMicrophone()
            }
            await MainActor.run { self?.ptt?.start() }
        }
    }

    private func beginVoiceTurn() {
        guard sttEnabled, conversation != nil else {
            return
        }
        // Barge-in (the Clippy behavior): starting to talk interrupts whatever
        // Clippy is currently saying or still generating, instead of being blocked.
        interruptSpeechAndResponse()
        usingDeepgram = false
        if let deepgram = deepgramSTT {
            do {
                try deepgram.start()
                usingDeepgram = true
            } catch {
                log("deepgram start failed: \(error)")
            }
        }
        if !usingDeepgram {
            do {
                try speech?.start()
            } catch {
                log("apple stt start failed: \(error)")
                return
            }
        }
        pendingIdle?.cancel()
        if let frame = mascot?.frame { chatBubble?.setAnchor(frame) }
        chatBubble?.showReply("Listening…")
        log("ptt: listening (deepgram=\(usingDeepgram))")
    }

    private func endVoiceTurn() {
        if usingDeepgram, let deepgram = deepgramSTT {
            deepgram.finish { [weak self] transcript in self?.handleTranscript(transcript) }
            return
        }
        // Apple fallback: 400ms tail so trailing words aren't clipped, then finalize.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let speech = self.speech else { return }
            self.handleTranscript(speech.stop())
        }
    }

    private func handleTranscript(_ transcript: String) {
        log("ptt: heard \"\(transcript)\"")
        if transcript.isEmpty {
            chatBubble?.hide()
            return
        }
        sendMessage(transcript)
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

        let brain = conversation
        // Give Clippy eyes: capture the screen so the model can Read it and point
        // accurately. The path + pixel size go in the message; the model decides
        // whether to look. We keep the shot to map its coordinates back to the screen.
        let shot = ScreenPerception.captureToFile()
        lastShot = shot
        let brainMessage = Self.augmentWithScreenshot(text, shot)
        currentBrainTask = Task { [weak self] in
            for await chunk in brain.stream(brainMessage) {
                if Task.isCancelled { break }
                await MainActor.run {
                    switch chunk {
                    case .partial(let partial):
                        self?.showStreamingReply(partial)
                    case .final(let turn):
                        self?.receiveReply(turn)
                    }
                }
            }
        }
    }

    /// Stop any in-flight reply and spoken audio so a new utterance — or an
    /// explicit "Stop Talking" — takes over cleanly. Cancelling the consuming task
    /// also tears down the brain's subprocess via the stream's onTermination.
    private func interruptSpeechAndResponse() {
        currentBrainTask?.cancel()
        currentBrainTask = nil
        deepgramTTS?.stop()
        isTurnRunning = false
    }

    @objc private func stopTalking() {
        interruptSpeechAndResponse()
        overlay?.clear()
        chatBubble?.hide()
        scheduleNextIdle()
    }

    /// Prepend a note telling the model a fresh screenshot is on disk, so it can
    /// `Read` it to see the screen and point in that image's pixel space.
    private static func augmentWithScreenshot(_ text: String, _ shot: ScreenPerception.Screenshot?) -> String {
        guard let shot else { return text }
        let w = Int(shot.pixelSize.width), h = Int(shot.pixelSize.height)
        return """
        [Current screenshot of the user's screen: \(shot.path) (\(w)x\(h) px). \
        Read it with your Read tool when you need to see the screen to point at, find, \
        or describe something. Any [POINT]/[TARGET]/[HOVER]/[HIGHLIGHT]/[SHAPE] coordinates \
        you emit are pixels in THAT image (top-left origin).]

        \(text)
        """
    }

    /// Live partial text while the reply streams in. Tags (even half-typed) are
    /// stripped before display so a bracket never flashes in the bubble.
    private func showStreamingReply(_ text: String) {
        if let frame = mascot?.frame { chatBubble?.setAnchor(frame) }
        let display = GroundingParser.stripForStreaming(text)
        if !display.isEmpty { chatBubble?.showReply(display) }
    }

    private func receiveReply(_ turn: AgentTurn) {
        isTurnRunning = false
        if let frame = mascot?.frame { chatBubble?.setAnchor(frame) }
        let parsed = GroundingParser.parse(turn.text)
        // Errors show their message as-is; otherwise show only the stripped speech.
        // A tag-only reply (no spoken text) shows nothing — never the raw brackets.
        let spoken = turn.isError ? turn.text : parsed.spokenText
        if spoken.isEmpty {
            chatBubble?.hide()
        } else {
            chatBubble?.showReply(spoken)
            if ttsEnabled, !turn.isError { deepgramTTS?.speak(spoken) }
        }
        log("clippy: \(turn.text.prefix(120))")

        if !turn.isError, !parsed.tags.isEmpty {
            presentGrounding(parsed.tags)
            return
        }
        overlay?.clear()
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

    /// Render parsed grounding directives: draw the marks, and move Clippy beside the
    /// first anchored target so it points at it with the matching body gesture.
    private func presentGrounding(_ rawTags: [GroundingTag]) {
        guard let mascot, let screen = NSScreen.main else {
            return
        }
        // The model emitted coordinates in the screenshot's pixel space; map them onto
        // the actual screen so the ring and Clippy's body land in the right place.
        let tags: [GroundingTag]
        if let shot = lastShot {
            tags = rawTags.map { $0.inScreenSpace(imageSize: shot.pixelSize, display: screen.frame) }
        } else {
            tags = rawTags
        }
        overlay?.show(tags.compactMap(AnnotationMark.init(tag:)), on: screen)
        // Auto-dismiss the marks so they don't linger on screen forever.
        overlayDismiss?.cancel()
        if tags.contains(where: { AnnotationMark(tag: $0) != nil }) {
            let dismiss = DispatchWorkItem { [weak self] in self?.overlay?.clear() }
            overlayDismiss = dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: dismiss)
        }

        if let anchor = tags.first(where: { $0.anchor != nil })?.anchor {
            // Point at a target with Clippy's body.
            pendingIdle?.cancel()
            let size = mascot.frame.size
            let origin = GroundingDirector.parkOrigin(beside: anchor, mascotSize: size, in: screen.visibleFrame)
            mascot.move(to: origin, animated: true)
            let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            playOnce(GroundingDirector.gesture(from: center, to: anchor).rawValue)
            chatBubble?.setAnchor(mascot.frame)
        } else if let animation = firstActAnimation(in: tags) {
            // Emote: Clippy performs the animation it asked for, in place.
            pendingIdle?.cancel()
            if playOnce(animation) == false {
                log("unknown animation requested: \(animation)")
                scheduleNextIdle()
            }
        }
    }

    private func firstActAnimation(in tags: [GroundingTag]) -> String? {
        for tag in tags {
            if case let .act(animation) = tag { return animation }
        }
        return nil
    }

    /// Plays `name` once, holding-then-exiting branched animations and returning to
    /// idle when it ends. Returns false if `name` isn't in the character pack.
    @discardableResult
    private func playOnce(_ name: String) -> Bool {
        guard let mascot else { return false }
        return mascot.play(name) { [weak self, weak mascot] _, state in
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

        // Only offer "Stop Talking" while there is something to stop.
        if isTurnRunning || (deepgramTTS?.isSpeaking ?? false) {
            let stop = NSMenuItem(title: "Stop Talking", action: #selector(stopTalking), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
        }

        let animate = NSMenuItem(title: "Animate!", action: #selector(animateNow), keyEquivalent: "")
        animate.target = self
        menu.addItem(animate)

        let mute = NSMenuItem(title: "Mute Sounds", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.state = (mascot?.isMuted ?? false) ? .on : .off
        menu.addItem(mute)

        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for model in ClippyModel.all {
            let item = NSMenuItem(title: model.displayName, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.id
            item.state = (model.id == selectedModel.id) ? .on : .off
            modelMenu.addItem(item)
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        let sttItem = NSMenuItem(title: "Voice input (hold ⌃⌥)", action: #selector(toggleSTT), keyEquivalent: "")
        sttItem.target = self
        sttItem.state = sttEnabled ? .on : .off
        menu.addItem(sttItem)

        let ttsItem = NSMenuItem(title: "Speak replies", action: #selector(toggleTTS), keyEquivalent: "")
        ttsItem.target = self
        ttsItem.state = ttsEnabled ? .on : .off
        menu.addItem(ttsItem)

        let voiceItem = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        let voiceMenu = NSMenu()
        for voice in ClippyVoice.all {
            let item = NSMenuItem(title: voice.displayName, action: #selector(selectVoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = voice.id
            item.state = (voice.id == selectedVoice.id) ? .on : .off
            voiceMenu.addItem(item)
        }
        voiceItem.submenu = voiceMenu
        menu.addItem(voiceItem)

        let permItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        let permMenu = NSMenu()
        let axItem = NSMenuItem(title: "Accessibility — voice hotkey + control", action: #selector(grantAccessibility), keyEquivalent: "")
        axItem.target = self
        axItem.state = AccessibilityPermission.isTrusted ? .on : .off
        permMenu.addItem(axItem)
        let screenItem = NSMenuItem(title: "Screen Recording — see the screen", action: #selector(grantScreenRecording), keyEquivalent: "")
        screenItem.target = self
        screenItem.state = ScreenPerception.hasPermission ? .on : .off
        permMenu.addItem(screenItem)
        let micItem = NSMenuItem(title: "Microphone — talk to Clippy", action: #selector(grantMicrophone), keyEquivalent: "")
        micItem.target = self
        micItem.state = MicrophonePermission.isGranted ? .on : .off
        permMenu.addItem(micItem)
        permItem.submenu = permMenu
        menu.addItem(permItem)

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

    @objc private func toggleSTT() {
        sttEnabled.toggle()
        UserDefaults.standard.set(sttEnabled, forKey: "ClippySTTEnabled")
    }

    @objc private func toggleTTS() {
        ttsEnabled.toggle()
        UserDefaults.standard.set(ttsEnabled, forKey: "ClippyTTSEnabled")
        if !ttsEnabled { deepgramTTS?.stop() }
    }

    @objc private func grantAccessibility() {
        _ = AccessibilityPermission.requestIfNeeded(prompt: true)
        openPrivacyPane("Privacy_Accessibility")
    }

    @objc private func grantScreenRecording() {
        _ = ScreenPerception.requestPermission()
        openPrivacyPane("Privacy_ScreenCapture")
    }

    @objc private func grantMicrophone() {
        Task { _ = await SpeechCapture.requestMicrophone() }
        openPrivacyPane("Privacy_Microphone")
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func selectVoice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let voice = ClippyVoice.by(id: id) else {
            return
        }
        selectedVoice = voice
        UserDefaults.standard.set(id, forKey: "ClippyVoiceID")
        deepgramTTS?.voiceModel = id
        log("voice: \(id)")
        deepgramTTS?.speak("It looks like you changed my voice. How's this?")
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let model = ClippyModel.by(id: id) else {
            return
        }
        selectedModel = model
        UserDefaults.standard.set(id, forKey: "ClippySelectedModelID")
        setUpBrain()
        log("model selected: \(id)")
        if let frame = mascot?.frame { chatBubble?.setAnchor(frame) }
        chatBubble?.showReply("Switched to \(model.displayName).")
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
        // Always on: the local MCP server (ClippyMCP) relays the model's tool calls
        // into this file, and debug commands use it too. Env var overrides the path.
        let path = ProcessInfo.processInfo.environment["CLIPPY_CMD_FILE"] ?? Self.defaultCommandFilePath()
        FileManager.default.createFile(atPath: path, contents: Data())
        commandTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.drainCommands(at: path)
            }
        }
    }

    private static func defaultCommandFilePath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("Clippy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("cmd.txt").path
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
            } else if command.hasPrefix("ground:") {
                let parsed = GroundingParser.parse(String(command.dropFirst(7)))
                chatBubble?.showReply(parsed.spokenText.isEmpty ? "(pointing)" : parsed.spokenText)
                presentGrounding(parsed.tags)
            } else if command == "clearground" {
                overlay?.clear()
            } else if command.hasPrefix("act:") {
                presentGrounding([.act(animation: String(command.dropFirst(4)).trimmingCharacters(in: .whitespaces))])
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
