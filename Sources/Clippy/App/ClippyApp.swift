import AppKit
import ClippyCore

@main
@MainActor
final class ClippyApp: NSObject, NSApplicationDelegate {
    private static let bodyScaleKey = "ClippyBodyScale"

    private var clippy: Clippy?
    private var pendingIdle: DispatchWorkItem?

    private var chatBubble: ClippyBubbleController?
    private var overlay: AnnotationOverlayWindow?
    private var permissionDrag: PermissionDragController?
    private var statusItem: NSStatusItem?
    private var retroMenu = RetroMenuController()
    private var ptt: PushToTalkMonitor?
    private var speech: SpeechCapture?
    private var deepgramSTT: DeepgramVoiceCapture?
    private var tts: XAITTS?
    private var providerKeys: ProviderKeysController?
    private var usingDeepgram = false
    private var codexComputerControlConversation: (any AgentBrain)?
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
    private var bodyScale: ClippyBodyScale = {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: ClippyApp.bodyScaleKey) != nil else {
            return .default
        }
        return ClippyBodyScale(defaults.double(forKey: ClippyApp.bodyScaleKey))
    }()
    private var isTurnRunning = false
    private var currentBrainTask: Task<Void, Never>?
    private var lastShot: ScreenPerception.Screenshot?
    private var overlayDismiss: DispatchWorkItem?
    private var turnProgressItems: [DispatchWorkItem] = []
    private var turnTimeoutItem: DispatchWorkItem?
    private var turnHasStreamingText = false
    private var ttsSpokenChars = 0   // how much of the streaming reply has been queued to TTS
    private var commandTimer: Timer?
    private var activeActivityState: AgentActivityState = .idle
    private var isClippyHidden = false
    private var guidedTarget: GuidedTarget?
    private var guidedTargetClickMonitor: Any?
    private var guidedTargetHoverMonitor: Any?
    private var guidedTargetExpiry: DispatchWorkItem?
    private var guidedHoverRest: DispatchWorkItem?
    private var nextGuidedTargetRound = 0
    private let guidedTargetMaxRounds = 4

    private struct VisualGroundingContext: Sendable {
        let originalUserText: String
        let screenshotPath: String?
        let screenshotPixelWidth: Int
        let screenshotPixelHeight: Int
        let desktopContext: DesktopContextSnapshot?
    }

    private struct GuidedTarget: Sendable {
        enum Kind: Sendable, Equatable { case click, hover }

        let kind: Kind
        let center: CGPoint
        let radius: CGFloat
        let label: String
        let round: Int
    }

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
        disarmGuidedTarget(reason: "terminate")
        log("applicationWillTerminate")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        RetroFont.registerBundledFonts()
        startClippy(Self.makeClippy(bodyScale: bodyScale))
        overlay = AnnotationOverlayWindow()
        setUpBrain()
        setUpVoice()
        startCommandChannel()
    }

    // MARK: - Clippy setup

    private static func makeClippy(bodyScale: ClippyBodyScale) -> Clippy {
        do {
            return try Clippy(packRoot: clippyResourceRoot(), bodyScale: bodyScale)
        } catch {
            fatalError("Clippy resources failed to load: \(error)")
        }
    }

    private func startClippy(_ clippy: Clippy) {
        let bubble = ClippyBubbleController(spec: clippy.spec)

        self.clippy = clippy
        self.chatBubble = bubble

        bubble.setAnchor(clippy.frame)
        bubble.setAnchorWindow(clippy.windowController.window)
        bubble.configure { [weak self] text in
            self?.sendMessage(text)
        }
        clippy.windowController.onFrameChanged = { [weak self] frame in
            self?.chatBubble?.setAnchor(frame, repositionVisible: false)
        }
        clippy.windowController.rightClickHandler = { [weak self] event, view in
            let point = view.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            self?.showRetroMenu(topLeft: point)
        }
        clippy.windowController.onCharacterClick = { [weak self] in
            self?.toggleChat()
        }
        setUpMenuBarItem()
        clippy.show()
        clippy.play(clippy.spec.greetingAnimationName) { [weak self] _, _ in
            self?.scheduleNextIdle()
        }
        bubble.showMessageForReading(clippy.spec.greetingText)
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
        guard let clippy, !isTurnRunning, isClippyHidden == false else {
            return
        }
        let name = clippy.idleAnimationNames.randomElement() ?? "RestPose"
        clippy.play(name) { [weak self, weak clippy] _, endState in
            switch endState {
            case .waiting:
                clippy?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    // MARK: - Brain

    private func setUpBrain() {
        codexComputerControlConversation = nil
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch selectedModel.backend {
        case .claude:
            if let cli = LocalCLIConversation.locateBinary() {
                conversation = LocalCLIConversation(binaryPath: cli, workingDirectory: home, model: selectedModel.id)
                log("brain: claude \(selectedModel.id)")
                prewarmBrain()
            } else {
                conversation = nil
                log("brain disabled: claude CLI not found")
            }
        case .codex:
            if let cli = CodexConversation.locateBinary() {
                conversation = CodexConversation(binaryPath: cli, model: selectedModel.id, workingDirectory: home)
                log("brain: codex \(selectedModel.id)")
                prewarmBrain()
            } else {
                conversation = nil
                log("brain disabled: codex CLI not found")
            }
        }
    }

    private func computerControlBrain() -> (any AgentBrain)? {
        if selectedModel.backend == .codex {
            return conversation
        }
        if let codexComputerControlConversation {
            return codexComputerControlConversation
        }
        guard BrainDiscovery.codexSignedIn(),
              let cli = CodexConversation.locateBinary()
        else {
            return nil
        }
        let brain = CodexConversation(
            binaryPath: cli,
            model: ClippyModel.gpt55.id,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        codexComputerControlConversation = brain
        log("brain: codex \(ClippyModel.gpt55.id) computer-control")
        Task {
            await brain.prepare()
        }
        return brain
    }

    private func prewarmBrain() {
        let brain = conversation
        Task {
            await brain?.prepare()
        }
    }

    // MARK: - Voice (hold Control+Option; Deepgram STT + xAI TTS)

    private func setUpVoice() {
        configureVoiceProviders()
        deepgramSTT?.onPartialTranscript = { [weak self] text in
            guard let self, !self.isTurnRunning, self.isClippyHidden == false else { return }
            if let frame = self.clippy?.frame { self.chatBubble?.setAnchor(frame) }
            self.chatBubble?.showStatus(text)
        }

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

        if !ClippySecrets.missingRequiredProviderNames.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showProviderKeys()
            }
        }
    }

    private func configureVoiceProviders() {
        deepgramSTT?.cancel()
        tts?.stop()
        deepgramSTT = DeepgramVoiceCapture()
        tts = XAITTS(voiceID: selectedVoice.id)
        speech = deepgramSTT == nil ? SpeechCapture() : nil
        log("voice: deepgram STT=\(deepgramSTT != nil) xAI TTS=\(tts != nil)")
    }

    private func beginVoiceTurn() {
        if isClippyHidden {
            showClippy()
            log("wake shortcut: clippy shown")
            return
        }
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
        if isClippyHidden == false {
            if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
            chatBubble?.showStatus("Listening...")
        }
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
        sendMessage(transcript, inputMode: .voice)
    }

    private func toggleChat() {
        guard let clippy, let chatBubble else {
            return
        }
        if isClippyHidden {
            showClippy()
        }
        chatBubble.setAnchor(clippy.frame)
        if chatBubble.isInputMode {
            chatBubble.hide()
            return
        }
        clippy.play(clippy.spec.openInputAnimationName) { [weak clippy] _, state in
            if state == .waiting {
                clippy?.exitCurrentAnimation()
            }
        }
        chatBubble.openInput()
    }

    private func sendMessage(_ text: String, inputMode: AssistantInputMode = .text) {
        guard let chatBubble else {
            return
        }
        guard !isTurnRunning else {
            if isClippyHidden == false {
                syncBubbleAnchorToClippy()
                chatBubble.showReplyForReading("(One sec - still working on your last message.)")
            }
            return
        }
        let needsToolLane = ClippyAgentInstructions.shouldUseCodexToolLane(text: text, inputMode: inputMode)
        let needsComputerControl = ClippyAgentInstructions.shouldUseComputerControl(text: text, inputMode: inputMode)
        let needsAnnotationTool = ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: text, inputMode: inputMode)
        let activeBrain = needsToolLane ? (computerControlBrain() ?? conversation) : conversation
        guard let activeBrain else {
            if isClippyHidden == false {
                syncBubbleAnchorToClippy()
                chatBubble.showReplyForReading("(My local brain isn't installed.)")
            }
            return
        }
        isTurnRunning = true
        turnHasStreamingText = false
        cancelTurnProgressUpdates()
        pendingIdle?.cancel()
        log("user: \(text)")

        let brain = activeBrain
        if needsComputerControl {
            log("routing: codex computer-control requested")
        } else if needsAnnotationTool {
            log("routing: codex annotation requested")
        }
        let desktopContext = DesktopContextSnapshot.capture()
        log("desktop-context: \(desktopContext.logSummary)")
        // Give Clippy eyes on every turn so short phrases like "do this" and
        // typed bubble turns still carry the real app/window context underneath.
        let wantsScreen = ClippyAgentInstructions.shouldAttachScreenshot(text: text, inputMode: inputMode)
        let screenshotScreen = desktopContext.targetScreen() ?? screenForClippy()
        let shot = wantsScreen ? captureCleanTurnScreenshot(screen: screenshotScreen) : nil
        lastShot = shot
        if let shot {
            log("screen-capture: index=\(shot.screenIndex) frame=\(shot.screenFrame) pixels=\(Int(shot.pixelSize.width))x\(Int(shot.pixelSize.height))")
        } else if wantsScreen {
            log("screen-capture: unavailable")
        } else {
            log("screen-capture: skipped")
        }
        if isClippyHidden == false {
            syncBubbleAnchorToClippy()
            chatBubble.recordUserLine(text)
            chatBubble.showThinking(shot == nil ? "Starting the brain" : "Sending the screen")
        }
        scheduleTurnProgressUpdates(wantsScreen: wantsScreen, attachedScreenshot: shot != nil)
        scheduleTurnTimeout(reason: needsAnnotationTool ? "visual-grounding" : "message")
        playActivityState(.thinking)
        // Tell the brain how this turn arrives and leaves: spoken-and-transcribed input
        // (read past STT typos) and/or spoken output (write for the ear).
        let speaking = ttsEnabled && tts != nil
        let brainMessage = ClippyAgentInstructions.brainMessage(
            text: text,
            screenshotPath: shot?.path,
            screenshotPixelWidth: Int(shot?.pixelSize.width ?? 0),
            screenshotPixelHeight: Int(shot?.pixelSize.height ?? 0),
            inputMode: inputMode,
            speaking: speaking,
            desktopContext: desktopContext,
            requiresVisualGrounding: needsAnnotationTool)
        let visualGroundingContext = needsAnnotationTool
            ? VisualGroundingContext(
                originalUserText: text,
                screenshotPath: shot?.path,
                screenshotPixelWidth: Int(shot?.pixelSize.width ?? 0),
                screenshotPixelHeight: Int(shot?.pixelSize.height ?? 0),
                desktopContext: desktopContext
            )
            : nil
        ttsSpokenChars = 0
        currentBrainTask = Task { [weak self] in
            for await chunk in brain.stream(brainMessage) {
                if Task.isCancelled { break }
                await MainActor.run {
                    switch chunk {
                    case .status(let status):
                        self?.showTurnProgress(status)
                    case .partial(let partial):
                        if visualGroundingContext == nil {
                            self?.showStreamingReply(partial)
                            self?.speakStreaming(partial, final: false)
                        }
                    case .final(let turn):
                        self?.receiveReply(
                            turn,
                            visualGroundingContext: visualGroundingContext,
                            brain: brain
                        )
                    }
                }
            }
        }
    }

    private func scheduleTurnProgressUpdates(wantsScreen: Bool, attachedScreenshot: Bool) {
        let screenStatus = attachedScreenshot ? "Reading the screen" : "Waiting for first words"
        let phases: [(TimeInterval, String)] = [
            (1.0, wantsScreen ? screenStatus : "Waiting for first words"),
            (3.0, "Still thinking"),
            (6.0, "Still waiting on the model"),
            (10.0, "Still working"),
        ]
        for (delay, status) in phases {
            let work = DispatchWorkItem { [weak self] in
                self?.showTurnProgress(status)
            }
            turnProgressItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func showTurnProgress(_ status: String) {
        guard isTurnRunning, !turnHasStreamingText, isClippyHidden == false else { return }
        syncBubbleAnchorToClippy()
        chatBubble?.updateThinking(status)
    }

    private func cancelTurnProgressUpdates() {
        turnProgressItems.forEach { $0.cancel() }
        turnProgressItems.removeAll()
    }

    private func scheduleTurnTimeout(reason: String) {
        turnTimeoutItem?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.isTurnRunning else { return }
            self.log("turn-timeout: reason=\(reason)")
            self.currentBrainTask?.cancel()
            self.currentBrainTask = nil
            self.receiveReply(AgentTurn(
                text: "Codex model stream timed out before a final response.",
                isError: true
            ))
        }
        turnTimeoutItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 50, execute: timeout)
    }

    private func cancelTurnTimeout() {
        turnTimeoutItem?.cancel()
        turnTimeoutItem = nil
    }

    private func captureCleanTurnScreenshot(screen targetScreen: NSScreen?) -> ScreenPerception.Screenshot? {
        let clippyWindow = clippy?.windowController.window
        let bubbleWindow = chatBubble?.window
        let clippyWasVisible = clippyWindow?.isVisible == true
        let bubbleWasVisible = bubbleWindow?.isVisible == true

        overlay?.clear()
        bubbleWindow?.orderOut(nil)
        clippyWindow?.orderOut(nil)
        // Let WindowServer process the order-out before CGDisplayCreateImage.
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))

        let shot = ScreenPerception.captureToFile(screen: targetScreen)

        if clippyWasVisible {
            clippyWindow?.orderFrontRegardless()
        }
        if bubbleWasVisible {
            bubbleWindow?.orderFrontRegardless()
        }
        return shot
    }

    private func syncBubbleAnchorToClippy() {
        if let frame = clippy?.frame {
            chatBubble?.setAnchor(frame)
        }
    }

    /// Speak the reply as it streams: enqueue each newly-completed sentence (tags
    /// stripped) so Clippy talks before the whole reply lands. `final` flushes the
    /// trailing partial sentence. Brains that only produce a final result still speak
    /// the whole reply here.
    private func speakStreaming(_ text: String, final: Bool) {
        guard ttsEnabled, let tts else { return }
        let ns = text as NSString
        if ttsSpokenChars > ns.length { ttsSpokenChars = ns.length }
        let terminators = CharacterSet(charactersIn: ".!?\n")
        // Enqueue each complete sentence in the unspoken tail, one chunk at a time, so
        // even a reply that arrives as one large final chunk is spoken sentence by sentence.
        while ttsSpokenChars < ns.length {
            let tail = NSRange(location: ttsSpokenChars, length: ns.length - ttsSpokenChars)
            let stop = ns.rangeOfCharacter(from: terminators, options: [], range: tail)
            if stop.location == NSNotFound { break }
            let end = stop.location + stop.length
            enqueueSpoken(ns.substring(with: NSRange(location: ttsSpokenChars, length: end - ttsSpokenChars)), tts)
            ttsSpokenChars = end
        }
        // On the final chunk, speak any trailing sentence that has no terminator.
        if final, ttsSpokenChars < ns.length {
            enqueueSpoken(ns.substring(from: ttsSpokenChars), tts)
            ttsSpokenChars = ns.length
        }
    }

    private func enqueueSpoken(_ chunk: String, _ tts: XAITTS) {
        let clean = GroundingParser.strip(chunk)
        if let friendly = ClippyUserFacingError.replacement(for: clean, isError: false) {
            tts.enqueue(friendly)
        } else if !clean.isEmpty {
            tts.enqueue(clean)
        }
    }

    /// Stop any in-flight reply and spoken audio so a new utterance — or an
    /// explicit "Stop Talking" — takes over cleanly. Cancelling the consuming task
    /// also tears down the brain's subprocess via the stream's onTermination.
    private func interruptSpeechAndResponse() {
        currentBrainTask?.cancel()
        currentBrainTask = nil
        tts?.stop()
        cancelTurnProgressUpdates()
        cancelTurnTimeout()
        turnHasStreamingText = false
        isTurnRunning = false
    }

    @objc private func stopTalking() {
        interruptSpeechAndResponse()
        overlay?.clear()
        chatBubble?.hide()
        scheduleNextIdle()
    }


    /// Live partial text while the reply streams in. Tags (even half-typed) are
    /// stripped before display so a bracket never flashes in the bubble.
    private func showStreamingReply(_ text: String) {
        guard isClippyHidden == false else { return }
        if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
        let display = ClippyUserFacingError.replacement(for: text, isError: false)
            ?? VoiceSpeechTags.strip(GroundingParser.stripForStreaming(text))
        if !display.isEmpty {
            turnHasStreamingText = true
            cancelTurnProgressUpdates()
            chatBubble?.showReply(display)
        }
    }

    private func receiveReply(
        _ turn: AgentTurn,
        visualGroundingContext: VisualGroundingContext? = nil,
        brain: (any AgentBrain)? = nil
    ) {
        cancelTurnProgressUpdates()
        cancelTurnTimeout()
        currentBrainTask = nil
        turnHasStreamingText = false
        isTurnRunning = false
        if isClippyHidden {
            log("clippy: \(turn.text.prefix(120))")
            return
        }
        if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
        let friendlyFailure = ClippyUserFacingError.replacement(for: turn.text, isError: turn.isError)
        let replyText = friendlyFailure ?? turn.text
        let parsed = GroundingParser.parse(replyText)
        if visualGroundingContext != nil {
            log("visual-grounding-tags: renderable=\(renderableGroundingTagCount(in: parsed.tags)) total=\(parsed.tags.count)")
        }
        if shouldRepairVisualGrounding(turn: turn, parsed: parsed, context: visualGroundingContext) {
            repairVisualGrounding(context: visualGroundingContext!, previousTurn: turn, brain: brain)
            return
        }
        // Runtime failures get a Clippy-shaped sentence; normal replies show only
        // the stripped speech. A tag-only reply shows nothing — never raw brackets.
        let spoken = VoiceSpeechTags.strip(parsed.spokenText)
        if spoken.isEmpty {
            chatBubble?.hide()
        } else {
            chatBubble?.showReplyForReading(spoken)
        }
        // Flush any sentence not yet spoken. Streamed replies already spoke most of it
        // sentence-by-sentence; any non-streaming fallback speaks the whole reply here.
        if turn.isError == false {
            speakStreaming(replyText, final: true)
        }
        log("clippy: \(turn.text.prefix(120))")

        if !turn.isError, !parsed.tags.isEmpty {
            presentGrounding(parsed.tags)
            return
        }
        overlay?.clear()
        playActivityState(turn.isError ? .error : .attention)

        let animationName = turn.isError
            ? (clippy?.spec.errorAnimationName ?? "Alert")
            : (clippy?.spec.replyAnimationName ?? "Explain")
        clippy?.play(animationName) { [weak self, weak clippy] _, state in
            switch state {
            case .waiting:
                clippy?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    private func shouldRepairVisualGrounding(
        turn: AgentTurn,
        parsed: GroundingDirectives,
        context: VisualGroundingContext?
    ) -> Bool {
        guard context != nil, turn.isError == false else { return false }
        return renderableGroundingTagCount(in: parsed.tags) == 0
    }

    private func renderableGroundingTagCount(in tags: [GroundingTag]) -> Int {
        tags.filter(\.isRenderableVisual).count
    }

    private func repairVisualGrounding(
        context: VisualGroundingContext,
        previousTurn: AgentTurn,
        brain: (any AgentBrain)?
    ) {
        guard let brain else {
            receiveReply(previousTurn)
            return
        }
        log("visual-grounding-repair: missing renderable tags; retrying")
        isTurnRunning = true
        turnHasStreamingText = false
        ttsSpokenChars = 0
        syncBubbleAnchorToClippy()
        chatBubble?.showThinking("Adding screen marks")
        scheduleTurnTimeout(reason: "visual-grounding-repair")
        playActivityState(.thinking)
        let repairMessage = ClippyAgentInstructions.visualGroundingRepairMessage(
            originalUserText: context.originalUserText,
            previousAssistantText: previousTurn.text,
            screenshotPath: context.screenshotPath,
            screenshotPixelWidth: context.screenshotPixelWidth,
            screenshotPixelHeight: context.screenshotPixelHeight,
            desktopContext: context.desktopContext
        )
        currentBrainTask = Task { [weak self] in
            let repairTurn = await brain.send(repairMessage)
            if Task.isCancelled { return }
            await MainActor.run {
                self?.receiveReply(repairTurn)
            }
        }
    }

    /// Render parsed grounding directives: draw the marks, and move Clippy beside the
    /// first anchored target so it points at it with the matching body gesture.
    private func presentGrounding(_ rawTags: [GroundingTag]) {
        guard isClippyHidden == false else {
            return
        }
        guard let clippy else {
            return
        }
        let fallbackScreen = screenForClippy() ?? NSScreen.main ?? NSScreen.screens.first
        let screen = screenForLastShot() ?? fallbackScreen
        guard let screen else { return }
        // The model emitted coordinates in the screenshot's pixel space; map them onto
        // the actual screen so the ring and Clippy's body land in the right place.
        let tags: [GroundingTag]
        if let shot = lastShot {
            tags = rawTags.map { $0.inScreenSpace(imageSize: shot.pixelSize, display: shot.screenFrame) }
        } else {
            tags = rawTags
        }
        log("grounding-presented: renderable=\(renderableGroundingTagCount(in: tags)) total=\(tags.count)")
        log("grounding-beats: \(groundingBeatSummary(tags))")
        let marks = tags.compactMap(AnnotationMark.init(tag:))
        overlay?.showSequence(marks, on: screen)
        armGuidedTarget(from: tags)
        // Auto-dismiss the marks so they don't linger on screen forever.
        overlayDismiss?.cancel()
        if !marks.isEmpty {
            let dismiss = DispatchWorkItem { [weak self] in self?.overlay?.clear() }
            overlayDismiss = dismiss
            let drawDuration = marks.reduce(TimeInterval(0)) { $0 + $1.visualBeatDuration }
            DispatchQueue.main.asyncAfter(deadline: .now() + drawDuration + 6, execute: dismiss)
        }

        if let anchor = tags.first(where: { $0.anchor != nil })?.anchor {
            // Point at a target with Clippy's body.
            pendingIdle?.cancel()
            let size = clippy.frame.size
            let origin = GroundingDirector.parkOrigin(beside: anchor, clippySize: size, in: screen.visibleFrame)
            let finalFrame = CGRect(origin: origin, size: size)
            clippy.windowController.move(to: origin, animated: true) { [weak self, weak clippy] in
                if let frame = clippy?.frame {
                    self?.chatBubble?.setAnchor(frame)
                } else {
                    self?.chatBubble?.setAnchor(finalFrame)
                }
            }
            let center = CGPoint(x: finalFrame.midX, y: finalFrame.midY)
            playOnce(GroundingDirector.pointingAnimationName(from: center, to: anchor))
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

    private func groundingBeatSummary(_ tags: [GroundingTag]) -> String {
        tags.map { tag in
            switch tag {
            case let .point(point, label, _):
                return "point(\(Int(point.x)),\(Int(point.y)):\(label))"
            case let .target(point, radius, label, _):
                return "target(\(Int(point.x)),\(Int(point.y)),r\(Int(radius)):\(label))"
            case let .hover(point, radius, label, _):
                return "hover(\(Int(point.x)),\(Int(point.y)),r\(Int(radius)):\(label))"
            case let .highlight(point, radius, label, _):
                return "highlight(\(Int(point.x)),\(Int(point.y)),r\(Int(radius)):\(label))"
            case let .shape(kind, points, label, _):
                return "shape:\(kind.rawValue)(points:\(points.count):\(label))"
            case let .act(animation):
                return "act(\(animation))"
            }
        }.joined(separator: " | ")
    }

    private func armGuidedTarget(from tags: [GroundingTag]) {
        let round = nextGuidedTargetRound
        nextGuidedTargetRound = 0
        guard let target = firstGuidedTarget(in: tags, round: round) else {
            disarmGuidedTarget(reason: "no-target")
            return
        }
        guard target.round < guidedTargetMaxRounds else {
            disarmGuidedTarget(reason: "max-round")
            log("guided target suppress max-round label=\(target.label) round=\(target.round)")
            return
        }

        disarmGuidedTarget(reason: "rearm")
        guidedTarget = target
        log("guided target arm label=\(target.label) x=\(Int(target.center.x)) y=\(Int(target.center.y)) radius=\(Int(target.radius)) round=\(target.round) hover=\(target.kind == .hover)")

        switch target.kind {
        case .click:
            guidedTargetClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
                let point = NSEvent.mouseLocation
                Task { @MainActor [weak self] in
                    self?.handleGuidedTargetClick(at: point)
                }
            }
        case .hover:
            guidedTargetHoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                let point = NSEvent.mouseLocation
                Task { @MainActor [weak self] in
                    self?.handleGuidedTargetHover(at: point)
                }
            }
        }

        let expiry = DispatchWorkItem { [weak self] in
            guard let self, let guidedTarget = self.guidedTarget else { return }
            self.log("guided target expired label=\(guidedTarget.label)")
            self.disarmGuidedTarget(reason: "expired")
        }
        guidedTargetExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: expiry)
    }

    private func firstGuidedTarget(in tags: [GroundingTag], round: Int) -> GuidedTarget? {
        for tag in tags {
            switch tag {
            case let .target(center, radius, label, _):
                return GuidedTarget(kind: .click, center: center, radius: CGFloat(radius), label: label, round: round)
            case let .hover(center, radius, label, _):
                return GuidedTarget(kind: .hover, center: center, radius: CGFloat(radius), label: label, round: round)
            case .point, .highlight, .shape, .act:
                continue
            }
        }
        return nil
    }

    private func disarmGuidedTarget(reason: String) {
        guidedHoverRest?.cancel()
        guidedHoverRest = nil
        guidedTargetExpiry?.cancel()
        guidedTargetExpiry = nil
        if let monitor = guidedTargetClickMonitor {
            NSEvent.removeMonitor(monitor)
            guidedTargetClickMonitor = nil
        }
        if let monitor = guidedTargetHoverMonitor {
            NSEvent.removeMonitor(monitor)
            guidedTargetHoverMonitor = nil
        }
        if let target = guidedTarget, reason != "no-target" {
            log("guided target disarm label=\(target.label) round=\(target.round) reason=\(reason)")
        }
        guidedTarget = nil
    }

    private func handleGuidedTargetClick(at point: CGPoint) {
        guard let target = guidedTarget, target.kind == .click else { return }
        let distance = guidedTargetDistance(from: point, to: target.center)
        guard distance <= target.radius else {
            log("guided target off-target click label=\(target.label) distance=\(Int(distance))")
            return
        }
        log("guided target hit label=\(target.label) distance=\(Int(distance)) hoverRest=false")
        disarmGuidedTarget(reason: "hit")
        overlay?.clear()
        startGuidedTargetFollowUp(target: target, trigger: "clicked", point: point)
    }

    private func handleGuidedTargetHover(at point: CGPoint) {
        guard let target = guidedTarget, target.kind == .hover else { return }
        let distance = guidedTargetDistance(from: point, to: target.center)
        if distance > target.radius {
            guidedHoverRest?.cancel()
            guidedHoverRest = nil
            return
        }
        guard guidedHoverRest == nil else { return }
        let rest = DispatchWorkItem { [weak self] in
            guard let self, let current = self.guidedTarget, current.kind == .hover else { return }
            let currentPoint = NSEvent.mouseLocation
            let currentDistance = self.guidedTargetDistance(from: currentPoint, to: current.center)
            guard currentDistance <= current.radius else {
                self.guidedHoverRest = nil
                return
            }
            self.log("guided target hit label=\(current.label) distance=\(Int(currentDistance)) hoverRest=true")
            self.disarmGuidedTarget(reason: "hover")
            self.overlay?.clear()
            self.startGuidedTargetFollowUp(target: current, trigger: "hovered over", point: currentPoint)
        }
        guidedHoverRest = rest
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: rest)
    }

    private func guidedTargetDistance(from point: CGPoint, to center: CGPoint) -> CGFloat {
        hypot(point.x - center.x, point.y - center.y)
    }

    private func startGuidedTargetFollowUp(target: GuidedTarget, trigger: String, point: CGPoint) {
        guard !isTurnRunning else {
            log("guided target follow-up skipped label=\(target.label) reason=turn-running")
            return
        }
        guard target.round + 1 <= guidedTargetMaxRounds else {
            log("guided target follow-up skipped label=\(target.label) reason=max-round")
            return
        }
        guard let brain = computerControlBrain() ?? conversation else {
            log("guided target follow-up skipped label=\(target.label) reason=no-brain")
            return
        }

        isTurnRunning = true
        turnHasStreamingText = false
        cancelTurnProgressUpdates()
        pendingIdle?.cancel()
        ttsSpokenChars = 0

        let nextRound = target.round + 1
        let remainingRounds = max(0, guidedTargetMaxRounds - nextRound)
        nextGuidedTargetRound = nextRound
        log("guided target follow-up start label=\(target.label) round=\(nextRound) \(trigger)X=\(Int(point.x)) \(trigger)Y=\(Int(point.y))")

        let desktopContext = DesktopContextSnapshot.capture()
        log("desktop-context: \(desktopContext.logSummary)")
        let screenshotScreen = desktopContext.targetScreen() ?? screenForClippy()
        let shot = captureCleanTurnScreenshot(screen: screenshotScreen)
        lastShot = shot
        if let shot {
            log("screen-capture: index=\(shot.screenIndex) frame=\(shot.screenFrame) pixels=\(Int(shot.pixelSize.width))x\(Int(shot.pixelSize.height))")
        } else {
            log("screen-capture: unavailable")
        }

        if isClippyHidden == false {
            syncBubbleAnchorToClippy()
            chatBubble?.showThinking("Checking that step")
        }
        scheduleTurnProgressUpdates(wantsScreen: true, attachedScreenshot: shot != nil)
        scheduleTurnTimeout(reason: "guided-target-follow-up")
        playActivityState(.thinking)

        let message = ClippyAgentInstructions.guidedTargetFollowUpMessage(
            label: target.label,
            trigger: trigger,
            triggerPointX: Int(point.x),
            triggerPointY: Int(point.y),
            round: nextRound,
            remainingRounds: remainingRounds,
            screenshotPath: shot?.path,
            screenshotPixelWidth: Int(shot?.pixelSize.width ?? 0),
            screenshotPixelHeight: Int(shot?.pixelSize.height ?? 0),
            desktopContext: desktopContext
        )
        currentBrainTask = Task { [weak self] in
            for await chunk in brain.stream(message) {
                if Task.isCancelled { break }
                await MainActor.run {
                    switch chunk {
                    case .status(let status):
                        self?.showTurnProgress(status)
                    case .partial(let partial):
                        self?.showStreamingReply(partial)
                        self?.speakStreaming(partial, final: false)
                    case .final(let turn):
                        self?.receiveReply(turn)
                    }
                }
            }
        }
    }

    private func screenForLastShot() -> NSScreen? {
        guard let shot = lastShot else { return nil }
        if NSScreen.screens.indices.contains(shot.screenIndex) {
            let indexed = NSScreen.screens[shot.screenIndex]
            if indexed.frame == shot.screenFrame {
                return indexed
            }
        }
        if let matched = NSScreen.screens.first(where: { $0.frame == shot.screenFrame }) {
            return matched
        }
        guard NSScreen.screens.indices.contains(shot.screenIndex) else { return nil }
        return NSScreen.screens[shot.screenIndex]
    }

    private func screenForClippy() -> NSScreen? {
        guard let clippy else { return NSScreen.main ?? NSScreen.screens.first }
        return ScreenPerception.screen(containing: clippy.frame)
            ?? clippy.windowController.window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Plays `name` once, holding-then-exiting branched animations and returning to
    /// idle when it ends. Returns false if `name` isn't in the character pack.
    @discardableResult
    private func playOnce(_ name: String) -> Bool {
        guard let clippy else { return false }
        return clippy.play(name) { [weak self, weak clippy] _, state in
            switch state {
            case .waiting:
                clippy?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    private func playActivityState(_ state: AgentActivityState) {
        activeActivityState = state
        pendingIdle?.cancel()
        guard isClippyHidden == false else {
            return
        }
        guard state != .idle else {
            scheduleNextIdle()
            return
        }
        guard let binding = clippy?.spec.animation(for: state) else {
            scheduleNextIdle()
            return
        }
        if binding.repeatsUntilStateChange {
            playLooping(binding.animationName, while: state)
        } else {
            playTransient(binding.animationName)
        }
    }

    // MARK: - Visibility

    @objc private func toggleClippyVisibility() {
        if isClippyHidden {
            showClippy()
        } else {
            hideClippy()
        }
    }

    private func hideClippy() {
        guard isClippyHidden == false else { return }
        isClippyHidden = true
        updateMenuBarItem()
        pendingIdle?.cancel()
        chatBubble?.hide()
        overlay?.clear()
        permissionDrag?.hide()
        deepgramSTT?.cancel()
        usingDeepgram = false
        _ = speech?.stop()
        tts?.stop()
        clippy?.windowController.hide()
        log("clippy hidden")
    }

    private func showClippy() {
        guard isClippyHidden else { return }
        isClippyHidden = false
        updateMenuBarItem()
        clippy?.show()
        if let frame = clippy?.frame {
            chatBubble?.setAnchor(frame)
        }
        log("clippy shown")
        if isTurnRunning {
            playActivityState(activeActivityState)
        } else {
            scheduleNextIdle()
        }
    }

    private func playTransient(_ name: String) {
        clippy?.play(name) { [weak self, weak clippy] _, state in
            switch state {
            case .waiting:
                clippy?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    /// Plays an animation and keeps replaying it while that activity state remains visible.
    private func playLooping(_ name: String, while activityState: AgentActivityState) {
        clippy?.play(name) { [weak self] _, endState in
            guard let self else {
                return
            }
            switch endState {
            case .waiting:
                self.clippy?.exitCurrentAnimation()
            case .exited:
                if self.activeActivityState == activityState {
                    self.playLooping(name, while: activityState)
                }
            }
        }
    }

    // MARK: - Retro menu

    private func setUpMenuBarItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(menuBarItemClicked(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        updateMenuBarItem()
    }

    private func updateMenuBarItem() {
        guard let button = statusItem?.button else { return }
        button.image = Self.makeEyeStatusImage(hidden: isClippyHidden)
        button.imagePosition = .imageOnly
        button.toolTip = isClippyHidden ? "Show Clippy" : "Hide Clippy"
    }

    @objc private func menuBarItemClicked(_ sender: NSStatusBarButton) {
        let windowFrame = sender.convert(sender.bounds, to: nil)
        let screenFrame = sender.window?.convertToScreen(windowFrame)
            ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        showRetroMenu(topLeft: NSPoint(x: screenFrame.minX, y: screenFrame.minY - 4))
    }

    private func showRetroMenu(topLeft point: NSPoint) {
        retroMenu.show(items: makeRetroMenuItems(), topLeft: point)
    }

    private func makeRetroMenuItems() -> [RetroMenuItem] {
        var items: [RetroMenuItem] = [
            .action(clippy?.spec.chatMenuTitle ?? ClippySpec.current.chatMenuTitle) { [weak self] in
                self?.toggleChat()
            },
        ]

        if isTurnRunning || (tts?.isSpeaking ?? false) {
            items.append(.action("Stop Talking") { [weak self] in
                self?.stopTalking()
            })
        }

        items.append(.action("Animate!") { [weak self] in
            self?.animateNow()
        })

        items.append(.action(
            isClippyHidden ? "Show Clippy" : "Hide Clippy",
            detail: isClippyHidden ? "Hold Ctrl+Option" : nil,
            icon: isClippyHidden ? .eye : .eyeSlash
        ) { [weak self] in
            self?.toggleClippyVisibility()
        })

        items.append(.separator())
        items.append(.toggle("Mute Sounds", isOn: clippy?.isMuted ?? false) { [weak self] in
            self?.toggleMute()
        })
        items.append(.toggle("Voice Input (hold Ctrl+Option)", isOn: sttEnabled) { [weak self] in
            self?.toggleSTT()
        })
        items.append(.toggle("Speak Replies", isOn: ttsEnabled) { [weak self] in
            self?.toggleTTS()
        })

        let bodySizeItems: [RetroMenuItem] = [
            .action("- Smaller", detail: "25%") { [weak self] in
                self?.adjustBodyScale(by: -1)
            },
            .action("+ Bigger", detail: "25%") { [weak self] in
                self?.adjustBodyScale(by: 1)
            },
            .action("Reset Size", detail: "100%") { [weak self] in
                self?.setBodyScale(.default)
            },
        ]
        items.append(.submenu("Clippy Size", detail: bodyScale.percentTitle, items: bodySizeItems))

        let modelItems = ClippyModel.all.map { model in
            RetroMenuItem.choice(model.displayName, isSelected: model.id == selectedModel.id) { [weak self] in
                self?.selectModel(id: model.id)
            }
        }
        items.append(.separator())
        items.append(.submenu("Model", detail: selectedModel.displayName, items: modelItems))

        let voiceItems = ClippyVoice.all.map { voice in
            RetroMenuItem.choice(voice.displayName, isSelected: voice.id == selectedVoice.id) { [weak self] in
                self?.selectVoice(id: voice.id)
            }
        }
        items.append(.submenu("Voice", detail: selectedVoice.id, items: voiceItems))

        items.append(.separator())
        items.append(.action("Configure API Key...") { [weak self] in
            self?.showProviderKeys()
        })

        let permissionItems: [RetroMenuItem] = [
            .toggle("Accessibility", isOn: AccessibilityPermission.isTrusted) { [weak self] in
                self?.grantAccessibility()
            },
            .toggle("Screen Recording", isOn: ScreenPerception.hasPermission) { [weak self] in
                self?.grantScreenRecording()
            },
            .toggle("Microphone", isOn: MicrophonePermission.isGranted) { [weak self] in
                self?.grantMicrophone()
            },
        ]
        items.append(.submenu("Permissions", items: permissionItems))

        items.append(.separator())
        items.append(.action("Quit Clippy") { [weak self] in
            self?.quitClippy()
        })
        return items
    }

    private static func makeEyeStatusImage(hidden: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let eyeRect = rect.insetBy(dx: 2, dy: 4)
            let eye = NSBezierPath()
            eye.move(to: NSPoint(x: eyeRect.minX, y: eyeRect.midY))
            eye.curve(
                to: NSPoint(x: eyeRect.maxX, y: eyeRect.midY),
                controlPoint1: NSPoint(x: eyeRect.minX + 4, y: eyeRect.maxY),
                controlPoint2: NSPoint(x: eyeRect.maxX - 4, y: eyeRect.maxY)
            )
            eye.curve(
                to: NSPoint(x: eyeRect.minX, y: eyeRect.midY),
                controlPoint1: NSPoint(x: eyeRect.maxX - 4, y: eyeRect.minY),
                controlPoint2: NSPoint(x: eyeRect.minX + 4, y: eyeRect.minY)
            )
            eye.lineWidth = 1.4
            eye.stroke()
            NSBezierPath(ovalIn: NSRect(x: eyeRect.midX - 2, y: eyeRect.midY - 2, width: 4, height: 4)).fill()
            if hidden {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: rect.minX + 4, y: rect.minY + 4))
                slash.line(to: NSPoint(x: rect.maxX - 4, y: rect.maxY - 4))
                slash.lineWidth = 2
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func chatClicked() {
        toggleChat()
    }

    @objc private func animateNow() {
        pendingIdle?.cancel()
        guard let clippy else {
            return
        }
        let name = clippy.gestureAnimationNames.randomElement() ?? clippy.spec.fallbackGestureAnimationName
        clippy.play(name) { [weak self, weak clippy] _, endState in
            switch endState {
            case .waiting:
                clippy?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    @objc private func toggleMute() {
        clippy?.isMuted.toggle()
    }

    @objc private func toggleSTT() {
        sttEnabled.toggle()
        UserDefaults.standard.set(sttEnabled, forKey: "ClippySTTEnabled")
    }

    @objc private func toggleTTS() {
        ttsEnabled.toggle()
        UserDefaults.standard.set(ttsEnabled, forKey: "ClippyTTSEnabled")
        if !ttsEnabled { tts?.stop() }
    }

    private func adjustBodyScale(by steps: Int) {
        setBodyScale(bodyScale.adjusted(by: steps))
    }

    private func setBodyScale(_ scale: ClippyBodyScale) {
        bodyScale = scale
        UserDefaults.standard.set(scale.value, forKey: Self.bodyScaleKey)
        if let clippy {
            clippy.resizeBody(to: scale, in: screenForClippy()?.visibleFrame ?? NSScreen.main?.visibleFrame, animated: true)
        }
        log("body size: \(scale.percentTitle)")
        guard isClippyHidden == false else { return }
        syncBubbleAnchorToClippy()
        chatBubble?.showReplyForReading("Clippy size \(scale.percentTitle).")
    }

    @objc private func grantAccessibility() {
        _ = AccessibilityPermission.requestIfNeeded(prompt: true)
        showPermissionDialog(permissionName: "Accessibility", anchor: "Privacy_Accessibility")
    }

    @objc private func grantScreenRecording() {
        _ = ScreenPerception.requestPermission()
        showPermissionDialog(permissionName: "Screen Recording", anchor: "Privacy_ScreenCapture")
    }

    @objc private func grantMicrophone() {
        Task { _ = await SpeechCapture.requestMicrophone() }
        openPrivacyPane("Privacy_Microphone")
    }

    @objc private func openProviderKeys() {
        showProviderKeys()
    }

    private func showProviderKeys() {
        if providerKeys == nil {
            providerKeys = ProviderKeysController { [weak self] in
                self?.configureVoiceProviders()
            }
        }
        providerKeys?.showWindow(nil)
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Show the Codex-style permission dialog: a draggable Clippy tile + an
    /// "Open System Settings" button, so the user can drag Clippy into the privacy list.
    private func showPermissionDialog(permissionName: String, anchor: String) {
        permissionDrag?.hide()
        let controller = PermissionDragController(
            appURL: Bundle.main.bundleURL, permissionName: permissionName, settingsAnchor: anchor)
        permissionDrag = controller
        controller.show()
    }

    @objc private func selectVoice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        selectVoice(id: id)
    }

    private func selectVoice(id: String) {
        guard let voice = ClippyVoice.by(id: id) else { return }
        selectedVoice = voice
        UserDefaults.standard.set(id, forKey: "ClippyVoiceID")
        tts?.voiceID = id
        log("voice: \(id)")
        guard isClippyHidden == false else { return }
        tts?.speak("It looks like you changed my voice. [chuckle] How's this?")
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        selectModel(id: id)
    }

    private func selectModel(id: String) {
        guard let model = ClippyModel.by(id: id) else { return }
        selectedModel = model
        UserDefaults.standard.set(id, forKey: "ClippySelectedModelID")
        setUpBrain()
        log("model selected: \(id)")
        guard isClippyHidden == false else { return }
        if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
        chatBubble?.showReplyForReading("Switched to \(model.displayName).")
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
    /// headlessly: `ask:<text>`, `askfront:<bundle>|<url>|<text>`, `open`,
    /// `snapshot`, `move:`, `park:`, `state:`.
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
            } else if command.hasPrefix("askfront:") {
                askFront(command: String(command.dropFirst("askfront:".count)))
            } else if command == "open" {
                if isClippyHidden {
                    showClippy()
                }
                if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
                chatBubble?.openInput()
            } else if command == "snapshot" {
                writeSnapshot(index: 99, directory: snapshotDirectory ?? "/tmp")
                writeChatSnapshot(directory: snapshotDirectory ?? "/tmp")
            } else if command.hasPrefix("move:") {
                moveClippy(command: String(command.dropFirst(5)))
            } else if command.hasPrefix("park:") {
                parkClippy(command: String(command.dropFirst(5)))
            } else if command == "hide" {
                hideClippy()
            } else if command == "show" {
                showClippy()
            } else if command.hasPrefix("state:") {
                applyStateCommand(String(command.dropFirst(6)))
            } else if command.hasPrefix("ground:") {
                let parsed = GroundingParser.parse(String(command.dropFirst(7)))
                if isClippyHidden == false {
                    let spoken = VoiceSpeechTags.strip(parsed.spokenText)
                    chatBubble?.showReplyForReading(spoken.isEmpty ? "(pointing)" : spoken)
                    presentGrounding(parsed.tags)
                }
            } else if command == "clearground" {
                overlay?.clear()
            } else if command.hasPrefix("bodysize:") {
                applyBodySizeCommand(String(command.dropFirst("bodysize:".count)))
            } else if command.hasPrefix("act:") {
                presentGrounding([.act(animation: String(command.dropFirst(4)).trimmingCharacters(in: .whitespaces))])
            }
        }
    }

    private func askFront(command: String) {
        let parts = command.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            log("askfront: invalid command")
            return
        }
        let bundleID = parts[0].trimmingCharacters(in: .whitespaces)
        let url = parts[1].trimmingCharacters(in: .whitespaces)
        let prompt = parts[2].trimmingCharacters(in: .whitespaces)
        guard !bundleID.isEmpty, !prompt.isEmpty else {
            log("askfront: missing bundle or prompt")
            return
        }
        activateApp(bundleIdentifier: bundleID, url: url.isEmpty ? nil : url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.activateApp(bundleIdentifier: bundleID, url: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.sendMessage(prompt)
            }
        }
    }

    private func activateApp(bundleIdentifier: String, url: String?) {
        if let url, bundleIdentifier == "com.google.Chrome" {
            let escaped = url.replacingOccurrences(of: "\"", with: "\\\"")
            runAppleScript("""
            tell application id "com.google.Chrome"
              activate
              set testWindow to make new window
              set URL of active tab of testWindow to "\(escaped)"
              set index of testWindow to 1
              delay 0.2
              reload active tab of testWindow
            end tell
            """)
            return
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            app.activate(options: [.activateIgnoringOtherApps])
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        } else {
            log("askfront: app not found bundle=\(bundleIdentifier)")
        }
    }

    @discardableResult
    private func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        _ = script?.executeAndReturnError(&error)
        if let error {
            log("applescript error: \(error)")
            return false
        }
        return true
    }

    private func applyBodySizeCommand(_ raw: String) {
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch command {
        case "+", "plus", "increase", "bigger", "larger":
            adjustBodyScale(by: 1)
        case "-", "minus", "decrease", "smaller":
            adjustBodyScale(by: -1)
        case "reset", "default":
            setBodyScale(.default)
        default:
            let cleaned = command.replacingOccurrences(of: "%", with: "")
            guard let number = Double(cleaned) else { return }
            setBodyScale(ClippyBodyScale(number > 10 ? number / 100 : number))
        }
    }

    private func applyStateCommand(_ command: String) {
        guard let state = AgentActivityState(rawValue: command.trimmingCharacters(in: .whitespaces)) else {
            return
        }
        log("state: \(state.rawValue)")
        playActivityState(state)
    }

    private func moveClippy(command: String) {
        let parts = command.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else {
            return
        }
        clippy?.windowController.move(to: CGPoint(x: parts[0], y: parts[1]), animated: true) { [weak self] in
            if let frame = self?.clippy?.frame { self?.chatBubble?.setAnchor(frame) }
        }
    }

    private func parkClippy(command: String) {
        guard
            let edge = ClippyParkEdge(rawValue: command),
            let visibleFrame = screenForClippy()?.visibleFrame
        else {
            return
        }
        let size = clippy?.windowController.frame.size ?? CGSize(width: 160, height: 160)
        let margin: CGFloat = 24
        let origin: CGPoint
        switch edge {
        case .lowerLeft:
            origin = CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin)
        case .lowerRight:
            origin = CGPoint(x: visibleFrame.maxX - size.width - margin, y: visibleFrame.minY + margin)
        case .upperLeft:
            origin = CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.maxY - size.height - margin)
        case .upperRight:
            origin = CGPoint(x: visibleFrame.maxX - size.width - margin, y: visibleFrame.maxY - size.height - margin)
        }
        clippy?.windowController.move(to: origin, animated: true) { [weak self] in
            if let frame = self?.clippy?.frame { self?.chatBubble?.setAnchor(frame) }
        }
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
        guard let data = clippy?.snapshotPNGData() else {
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
