import AppKit
import ClippyCore
import Sparkle

@main
@MainActor
final class ClippyApp: NSObject, NSApplicationDelegate {
    private enum UserAnnotationMode {
        case quick
        case sticky
    }

    private static let bodyScaleKey = "ClippyBodyScale"
    private static let setupCompletedKey = "ClippySetupCompleted"
    private static let quickAnnotationHoldDelay: TimeInterval = 0.24
    private nonisolated static let shortcutModifierMask: NSEvent.ModifierFlags = [
        .control, .option, .command, .shift, .function
    ]

    private var clippy: Clippy?
    private var pendingIdle: DispatchWorkItem?

    private var chatBubble: ClippyBubbleController?
    private var overlay: AnnotationOverlayWindow?
    private var annotationHold: ModifierHoldMonitor?
    private var userAnnotationController: UserAnnotationController?
    private var userAnnotation: UserScreenAnnotation?
    private var permissionDrag: PermissionDragController?
    private var onboardingDemoWorkItems: [DispatchWorkItem] = []
    private var onboardingPermissionsRequested = Set<OnboardingPermission>()
    private var statusItem: NSStatusItem?
    private var retroMenu = RetroMenuController()
    private var ptt: PushToTalkMonitor?
    private var textInputShortcut: KeyboardShortcutMonitor?
    private var clearMarksGlobalMonitor: Any?
    private var clearMarksLocalMonitor: Any?
    private var speech: SpeechCapture?
    private var deepgramSTT: DeepgramVoiceCapture?
    private var tts: XAITTS?
    private var providerKeys: ProviderKeysController?
    private var setupProcess: Process?
    private var setupOutputPipe: Pipe?
    private var setupOutputHandle: FileHandle?
    private var openedSetupURLs = Set<String>()
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var isOnboardingActive = false
    private var usingDeepgram = false
    private var isVoiceCaptureActive = false
    private var isPushToTalkHeld = false
    private var voicePressID = 0
    private var voicePartialText = ""
    private var hideBubbleWhenSpeechFinishes = false
    private var spokenBubbleShownAt: Date?
    private var spokenBubbleHide: DispatchWorkItem?
    private var codexComputerControlConversation: (any AgentBrain)?
    private var sttEnabled = ClippyApp.defaultVoiceSetting(
        defaultsKey: "ClippySTTEnabled",
        disableEnvironmentKey: "CLIPPY_DISABLE_STT"
    )
    private var ttsEnabled = ClippyApp.defaultVoiceSetting(
        defaultsKey: "ClippyTTSEnabled",
        disableEnvironmentKey: "CLIPPY_DISABLE_TTS"
    )
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
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "ClippyVoiceID"),
           let saved = ClippyVoice.by(id: id) {
            return saved
        }
        defaults.set(ClippyVoice.default.id, forKey: "ClippyVoiceID")
        return .default
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
    private var activeUserRequest: ActiveUserRequest?
    private var lastShot: ScreenPerception.Screenshot?
    private var lastShots: [ScreenPerception.Screenshot] = []
    private var lastDesktopContext: DesktopContextSnapshot?
    private var turnProgressItems: [DispatchWorkItem] = []
    private var turnHasStreamingText = false
    private var ttsSpokenChars = 0   // how much of the streaming reply has been queued to TTS
    private var streamingReplySegmentID: String?
    private var commandTimer: Timer?
    private var activeActivityState: AgentActivityState = .idle
    private var activeTurnUsedUserAnnotation = false
    private var turnGeneration = 0
    private var isUserAnnotating = false
    private var isAnnotationHoldActive = false
    private var userAnnotationMode: UserAnnotationMode?
    private var annotationBeginWork: DispatchWorkItem?
    private var isClippyHidden = false
    private var guidedTarget: GuidedTarget?
    private var guidedTargetClickMonitor: Any?
    private var guidedTargetHoverMonitor: Any?
    private var guidedTargetExpiry: DispatchWorkItem?
    private var guidedHoverRest: DispatchWorkItem?
    private var guidedCompletedSteps: [String] = []
    private var nextGuidedTargetRound = 0
    private let guidedTargetMaxRounds = 4

    private struct ActiveUserRequest: Sendable {
        let text: String
        let inputMode: AssistantInputMode
        let attemptedModel: ClippyModel
    }

    private struct VisualGroundingContext: Sendable {
        let originalUserText: String
        let screenshotPath: String?
        let screenshotPixelWidth: Int
        let screenshotPixelHeight: Int
        let screenshots: [ClippyAgentInstructions.ScreenshotPromptContext]
        let desktopContext: DesktopContextSnapshot?
    }

    private struct GuidedTarget: Sendable {
        enum Kind: Sendable, Equatable { case click, hover }

        let kind: Kind
        let center: CGPoint
        let radius: CGFloat
        let label: String
        let round: Int
        let overallGoal: String
        let previousInstruction: String
    }

    private enum OnboardingPermission: CaseIterable, Hashable {
        case accessibility
        case screenRecording
        case fullDiskAccess
        case microphone

        var name: String {
            switch self {
            case .accessibility: "Accessibility"
            case .screenRecording: "Screen Recording"
            case .fullDiskAccess: "Full Disk Access"
            case .microphone: "Microphone"
            }
        }

        var settingsAnchor: String {
            switch self {
            case .accessibility: "Privacy_Accessibility"
            case .screenRecording: "Privacy_ScreenCapture"
            case .fullDiskAccess: "Privacy_AllFiles"
            case .microphone: "Privacy_Microphone"
            }
        }

        var isGranted: Bool {
            switch self {
            case .accessibility: AccessibilityPermission.isTrusted
            case .screenRecording: ScreenPerception.hasPermission
            case .fullDiskAccess: FullDiskAccessPermission.isGranted
            case .microphone: MicrophonePermission.isGranted
            }
        }

        var animationName: String {
            switch self {
            case .accessibility: "GetAttention"
            case .screenRecording: "Explain"
            case .fullDiskAccess: "Processing"
            case .microphone: "Alert"
            }
        }
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
        cancelOnboardingDemoWork()
        currentBrainTask?.cancel()
        currentBrainTask = nil
        conversation = nil
        codexComputerControlConversation = nil
        cancelSetupProcess()
        textInputShortcut?.stop()
        stopClearMarksShortcut()
        annotationHold?.stop()
        userAnnotationController?.cancel()
        ptt?.stop()
        log("applicationWillTerminate")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        RetroFont.registerBundledFonts()
        startClippy(Self.makeClippy(bodyScale: bodyScale))
        overlay = AnnotationOverlayWindow()
        setUpBrain()
        setUpVoice()
        setUpShortcuts()
        startCommandChannel()
        showInitialSetupIfNeeded()
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
            self?.handleSubmittedText(text)
        }
        clippy.windowController.onFrameChanged = { [weak self] frame in
            self?.chatBubble?.setAnchor(frame, repositionVisible: false)
        }
        clippy.windowController.rightClickHandler = { [weak self] event, view in
            let point = view.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            self?.showRetroMenu(topLeft: point)
        }
        clippy.windowController.onCharacterClick = { [weak self] in
            self?.handleCharacterClick()
        }
        clippy.windowController.onCharacterDoubleClick = { [weak self] in
            self?.handleCharacterDoubleClick()
        }
        clippy.windowController.onKeyDown = { [weak self] event in
            self?.handleClippyFocusedTyping(event) ?? false
        }
        setUpMenuBarItem()
        clippy.show()
        clippy.play(clippy.spec.greetingAnimationName) { [weak self] _, _ in
            self?.scheduleNextIdle()
        }
        bubble.showMessageForReading(clippy.spec.greetingText)
        scheduleDebugSnapshots()
    }

    private func setUpShortcuts() {
        let shortcut = KeyboardShortcutMonitor(keyCode: 49, modifiers: [.control]) { [weak self] in
            self?.showTextInputFromShortcut()
        }
        textInputShortcut = shortcut
        shortcut.start()

        let annotation = ModifierHoldMonitor(modifiers: [.control])
        annotation.onBegin = { [weak self] in self?.beginQuickUserAnnotationMode() }
        annotation.onEnd = { [weak self] in self?.finishQuickUserAnnotationMode() }
        annotation.onDoubleTap = { [weak self] in self?.toggleStickyUserAnnotationMode() }
        annotationHold = annotation
        annotation.start()
        startClearMarksShortcut()
    }

    private func handleCharacterClick() {
        if clearScreenMarks(reason: "clippy-click", includeUserAnnotation: false) {
            return
        }
        toggleChat()
    }

    private func handleCharacterDoubleClick() {
        guard !isOnboardingActive else { return }
        cancelUserAnnotationMode()
        if isClippyHidden {
            showClippy()
        }
        syncBubbleAnchorToClippy()
        cancelSpokenBubbleHide()
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        if isTurnRunning {
            showBusyInvocationOptions()
            return
        }
        let context = DesktopContextSnapshot.capture()
        lastDesktopContext = context
        log("double-click invoke: \(context.logSummary)")
        recommendInvocationOptions(for: context)
    }

    private func recommendInvocationOptions(for context: DesktopContextSnapshot) {
        guard let chatBubble else { return }
        guard let brain = conversation else {
            log("double-click recommendations unavailable: brain missing")
            showInvocationFallback()
            return
        }
        let screenshotScreen = context.targetScreen() ?? screenForClippy()
        let shots = captureTurnScreenshots(primaryScreen: screenshotScreen)
        let shot = primaryShot(in: shots, primaryScreen: screenshotScreen)
        lastShots = shots
        lastShot = shot
        if shots.isEmpty == false {
            logScreenCaptures(shots, primary: shot)
        } else {
            log("screen-capture: unavailable")
        }
        let screenshotContexts = Self.screenshotPromptContexts(for: shots, primary: shot)
        let prompt = ClippyAgentInstructions.brainMessage(
            text: ClippyInvocationSuggestions.recommendationPrompt(),
            screenshotPath: shot?.path,
            screenshotPixelWidth: Int(shot?.pixelSize.width ?? 0),
            screenshotPixelHeight: Int(shot?.pixelSize.height ?? 0),
            screenshots: screenshotContexts,
            inputMode: .text,
            speaking: false,
            desktopContext: context
        )
        let localImagePaths = Self.localImagePaths(for: shots)

        isTurnRunning = true
        activeUserRequest = nil
        activeTurnUsedUserAnnotation = false
        turnHasStreamingText = false
        streamingReplySegmentID = nil
        cancelSpokenBubbleHide()
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        cancelTurnProgressUpdates()
        pendingIdle?.cancel()
        turnGeneration += 1
        let turnID = turnGeneration
        syncBubbleAnchorToClippy()
        chatBubble.showThinking(shot == nil ? "Thinking" : "Reading the screen")
        playActivityState(.thinking)
        scheduleTurnProgressUpdates(wantsScreen: true, attachedScreenshot: shot != nil)

        currentBrainTask = Task { [weak self] in
            let finalTurn: AgentTurn?
            if let structuredBrain = brain as? any StructuredOutputAgentBrain {
                finalTurn = await structuredBrain.sendStructured(
                    prompt,
                    localImagePaths: localImagePaths,
                    outputSchema: ClippyInvocationSuggestions.recommendationSchema
                )
            } else {
                finalTurn = await brain.send(prompt, localImagePaths: localImagePaths)
            }
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, self.turnGeneration == turnID else { return }
                self.cancelTurnProgressUpdates()
                self.currentBrainTask = nil
                self.isTurnRunning = false
                guard let finalTurn, finalTurn.isError == false else {
                    let message = finalTurn?.text.prefix(160) ?? "no response"
                    self.log("double-click recommendations failed: \(message)")
                    self.showInvocationFallback()
                    return
                }
                guard let recommendation = ClippyInvocationSuggestions.parseRecommendation(from: finalTurn.text) else {
                    self.log("double-click recommendations empty: \(finalTurn.text.prefix(160))")
                    self.showInvocationFallback()
                    return
                }
                self.log("double-click recommendations: \(recommendation.suggestions.map(\.title).joined(separator: ", "))")
                self.showInvocationOptions(recommendation)
            }
        }
    }

    private func showInvocationOptions(_ recommendation: ClippyInvocationRecommendation) {
        guard let chatBubble else { return }
        let choices = recommendation.suggestions.map { suggestion in
            ClippyBubbleController.Choice(title: suggestion.title) { [weak self] in
                self?.runInvocationSuggestion(suggestion)
            }
        } + [
            ClippyBubbleController.Choice(title: ClippyInvocationSuggestions.manualInputTitle) { [weak self] in
                self?.showTextInputBubble()
            },
        ]
        _ = playOnce("GetAttention")
        chatBubble.showChoicesTyping(recommendation.message, choices: choices)
    }

    private func showInvocationFallback() {
        _ = playOnce("GetAttention")
        showTextInputBubble()
    }

    private func showBusyInvocationOptions() {
        guard let request = activeUserRequest else {
            chatBubble?.showReplyForReading("I'm working on it.")
            return
        }
        _ = playOnce("GetAttention")
        chatBubble?.showChoicesTyping("I'm still working. What now?", choices: [
            .init(title: "Stop and ask") { [weak self] in
                self?.interruptSpeechAndResponse()
                self?.showTextInputBubble()
            },
            .init(title: "Keep going") { [weak self] in
                self?.syncBubbleAnchorToClippy()
                self?.chatBubble?.showThinking("Still working")
            },
            .init(title: "Retry this") { [weak self] in
                self?.interruptSpeechAndResponse()
                self?.sendMessage(request.text, inputMode: request.inputMode)
            },
        ])
    }

    private func runInvocationSuggestion(_ suggestion: ClippyInvocationSuggestion) {
        log("double-click choice: \(suggestion.title)")
        sendMessage(suggestion.prompt, visibleUserLine: suggestion.title)
    }

    private func startClearMarksShortcut() {
        clearMarksGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard Self.isBareEscape(event) else { return }
            Task { @MainActor [weak self] in
                self?.clearScreenMarks(reason: "escape", includeUserAnnotation: true)
            }
        }
        clearMarksLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard Self.isBareEscape(event),
                  let self,
                  self.clearScreenMarks(reason: "escape", includeUserAnnotation: true)
            else {
                return event
            }
            return nil
        }
    }

    private func stopClearMarksShortcut() {
        if let clearMarksGlobalMonitor {
            NSEvent.removeMonitor(clearMarksGlobalMonitor)
        }
        if let clearMarksLocalMonitor {
            NSEvent.removeMonitor(clearMarksLocalMonitor)
        }
        clearMarksGlobalMonitor = nil
        clearMarksLocalMonitor = nil
    }

    private nonisolated static func isBareEscape(_ event: NSEvent) -> Bool {
        event.isARepeat == false
            && event.keyCode == 53
            && event.modifierFlags.intersection(shortcutModifierMask).isEmpty
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

    private func applySelectedModel(_ model: ClippyModel) {
        selectedModel = model
        UserDefaults.standard.set(model.id, forKey: "ClippySelectedModelID")
        setUpBrain()
    }

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
        guard sttEnabled else {
            log("voice: STT disabled; TTS \(ttsEnabled ? "enabled" : "disabled")")
            return
        }
        configureVoiceProviders()

        let monitor = PushToTalkMonitor(modifiers: [.control, .option])
        monitor.onBegin = { [weak self] in self?.beginVoiceTurn() }
        monitor.onEnd = { [weak self] in self?.endVoiceTurn() }
        self.ptt = monitor
        monitor.start()
    }

    private func configureVoiceProviders() {
        deepgramSTT?.cancel()
        tts?.stop()
        cancelSpokenBubbleHide()
        isVoiceCaptureActive = false
        usingDeepgram = false
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        deepgramSTT = DeepgramVoiceCapture()
        tts = nil
        speech = deepgramSTT == nil ? SpeechCapture() : nil
        installVoiceProviderCallbacks()
        log("voice: deepgram STT=\(deepgramSTT != nil) xAI TTS key=\(ClippySecrets.xaiAPIKey != nil)")
    }

    private static func defaultVoiceSetting(defaultsKey: String, disableEnvironmentKey: String) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard !environmentFlag(environment["CLIPPY_DISABLE_VOICE"]),
              !environmentFlag(environment[disableEnvironmentKey]) else {
            return false
        }
        return UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    private static func environmentFlag(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": return true
        default: return false
        }
    }

    private func installVoiceProviderCallbacks() {
        deepgramSTT?.onPartialTranscript = { [weak self] text in
            self?.showLiveTranscript(text)
        }
        speech?.onPartialTranscript = { [weak self] text in
            self?.showLiveTranscript(text)
        }
        if let tts {
            installTTSCallbacks(tts)
        }
    }

    private func installTTSCallbacks(_ tts: XAITTS) {
        tts.onSpeakingChanged = { [weak self] speaking in
            self?.handleTTSActivity(speaking)
        }
        tts.onError = { [weak self] message in
            self?.log("tts error: \(message)")
        }
    }

    private func activeTTS() -> XAITTS? {
        guard ttsEnabled else { return nil }
        if let tts {
            return tts
        }
        guard let tts = XAITTS(voiceID: selectedVoice.id) else {
            return nil
        }
        self.tts = tts
        installTTSCallbacks(tts)
        return tts
    }

    private func showLiveTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              isVoiceCaptureActive,
              !isTurnRunning,
              isClippyHidden == false else {
            return
        }
        voicePartialText = trimmed
        if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
        chatBubble?.showStatus(trimmed)
    }

    private func handleTTSActivity(_ speaking: Bool) {
        if speaking {
            pendingIdle?.cancel()
            cancelSpokenBubbleHide()
            return
        }
        if hideBubbleWhenSpeechFinishes {
            if isClippyHidden == false, !isTurnRunning {
                scheduleSpokenBubbleHideAfterSpeech()
            }
        }
        if !isTurnRunning {
            scheduleNextIdle()
        }
    }

    private func showSpokenReplyBubble(_ text: String) {
        hideBubbleWhenSpeechFinishes = true
        spokenBubbleShownAt = Date()
        cancelSpokenBubbleHide()
        chatBubble?.showReply(text)
    }

    private func scheduleSpokenBubbleHideAfterSpeech() {
        cancelSpokenBubbleHide()
        guard !isOnboardingActive else {
            hideBubbleWhenSpeechFinishes = false
            spokenBubbleShownAt = nil
            return
        }
        let visibleFor = spokenBubbleShownAt.map { Date().timeIntervalSince($0) } ?? 0
        let delay = ClippyBubbleController.spokenAutoHideDelay(visibleFor: visibleFor)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.spokenBubbleHide = nil
            guard self.hideBubbleWhenSpeechFinishes,
                  self.isClippyHidden == false,
                  !self.isOnboardingActive,
                  !self.isTurnRunning,
                  !(self.tts?.isSpeaking ?? false)
            else {
                return
            }
            self.hideBubbleWhenSpeechFinishes = false
            self.spokenBubbleShownAt = nil
            self.chatBubble?.hide()
            self.scheduleNextIdle()
        }
        spokenBubbleHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelSpokenBubbleHide() {
        spokenBubbleHide?.cancel()
        spokenBubbleHide = nil
    }

    private func beginVoiceTurn() {
        isPushToTalkHeld = true
        voicePressID += 1
        let pressID = voicePressID
        if isClippyHidden {
            showClippy()
            log("wake shortcut: clippy shown")
            return
        }
        guard sttEnabled, conversation != nil else {
            return
        }
        if needsVoicePermissionForCurrentProvider() {
            requestVoicePermissionForPushToTalk(pressID: pressID)
            return
        }
        startVoiceCapture()
    }

    private func needsVoicePermissionForCurrentProvider() -> Bool {
        if deepgramSTT != nil {
            return !MicrophonePermission.isGranted
        }
        return !MicrophonePermission.isGranted || SpeechCapture.speechAuthorizationStatus != .authorized
    }

    private func requestVoicePermissionForPushToTalk(pressID: Int) {
        let needsSpeechRecognition = (deepgramSTT == nil)
        if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
        chatBubble?.showStatus("Allow microphone access, then hold Control+Option again.")
        Task { [weak self] in
            let granted: Bool
            if needsSpeechRecognition {
                granted = await SpeechCapture.requestAuthorization()
            } else {
                granted = await SpeechCapture.requestMicrophone()
            }
            await MainActor.run {
                self?.finishVoicePermissionRequest(pressID: pressID, granted: granted)
            }
        }
    }

    private func finishVoicePermissionRequest(pressID: Int, granted: Bool) {
        guard pressID == voicePressID else { return }
        guard granted else {
            log("ptt: voice permission denied")
            chatBubble?.showReplyForReading("(Microphone access is off.)")
            return
        }
        guard isPushToTalkHeld else {
            return
        }
        startVoiceCapture()
    }

    private func startVoiceCapture() {
        // Barge-in: starting to talk interrupts whatever
        // Clippy is currently saying or still generating, instead of being blocked.
        interruptSpeechAndResponse()
        usingDeepgram = false
        isVoiceCaptureActive = false
        voicePartialText = ""
        hideBubbleWhenSpeechFinishes = false
        var captureStarted = false
        if let deepgram = deepgramSTT {
            do {
                try deepgram.start()
                usingDeepgram = true
                captureStarted = true
            } catch {
                log("deepgram start failed: \(error)")
            }
        }
        if !usingDeepgram {
            guard let speech else { return }
            do {
                try speech.start()
                captureStarted = true
            } catch {
                log("apple stt start failed: \(error)")
                return
            }
        }
        guard captureStarted else { return }
        isVoiceCaptureActive = true
        pendingIdle?.cancel()
        if isClippyHidden == false {
            if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
            chatBubble?.showStatus("Listening...")
        }
        log("ptt: listening (deepgram=\(usingDeepgram))")
    }

    private func endVoiceTurn() {
        isPushToTalkHeld = false
        guard isVoiceCaptureActive else { return }
        isVoiceCaptureActive = false
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
        guard let chatBubble else {
            showTextInputBubble()
            return
        }
        if chatBubble.isInputMode {
            chatBubble.hide()
            return
        }
        if chatBubble.consumeRecentInputDismissalByAnchorClick() {
            return
        }
        showTextInputBubble()
    }

    private func showTextInputFromShortcut() {
        cancelUserAnnotationMode()
        log("text shortcut: open input")
        showTextInputBubble()
    }

    private func handleClippyFocusedTyping(_ event: NSEvent) -> Bool {
        guard !isVoiceCaptureActive,
              !isUserAnnotating,
              !isOnboardingActive,
              let chatBubble
        else {
            return false
        }
        let inputAlreadyOpen = chatBubble.isInputMode
        guard ClippyBubbleController.acceptsExternalInputKey(
            keyCode: event.keyCode,
            characters: event.characters,
            modifierFlags: event.modifierFlags,
            inputAlreadyOpen: inputAlreadyOpen
        ) else {
            return false
        }
        if isClippyHidden {
            showClippy()
        }
        syncBubbleAnchorToClippy()
        pendingIdle?.cancel()
        let accepted = chatBubble.receiveExternalInputKey(event)
        if accepted, !inputAlreadyOpen {
            log("focused-type: captured keyCode=\(event.keyCode)")
            clippy?.play(clippy?.spec.openInputAnimationName ?? "GetAttention") { [weak clippy] _, state in
                if state == .waiting {
                    clippy?.exitCurrentAnimation()
                }
            }
        }
        return accepted
    }

    private func beginQuickUserAnnotationMode() {
        guard userAnnotationMode != .sticky else {
            return
        }
        isAnnotationHoldActive = true
        annotationBeginWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.startQuickUserAnnotationModeIfStillHolding()
        }
        annotationBeginWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.quickAnnotationHoldDelay, execute: work)
    }

    private func startQuickUserAnnotationModeIfStillHolding() {
        guard isAnnotationHoldActive,
              userAnnotationMode != .sticky,
              !isTurnRunning,
              !isVoiceCaptureActive,
              !isOnboardingActive
        else {
            return
        }
        if isClippyHidden {
            showClippy()
        }
        userAnnotationMode = .quick
        isUserAnnotating = true
        pendingIdle?.cancel()
        overlay?.clear()
        let controller = userAnnotationController ?? UserAnnotationController()
        userAnnotationController = controller
        controller.begin(existing: userAnnotation)
        syncBubbleAnchorToClippy()
        chatBubble?.showStatus("Annotate mode. Drag to mark; release Control when done.")
        _ = playOnce("GetAttention")
        log("user-annotation: quick-begin")
    }

    private func finishQuickUserAnnotationMode() {
        isAnnotationHoldActive = false
        annotationBeginWork?.cancel()
        annotationBeginWork = nil
        guard userAnnotationMode == .quick else { return }
        finishCurrentUserAnnotationMode(logReason: "quick")
    }

    private func toggleStickyUserAnnotationMode() {
        isAnnotationHoldActive = false
        annotationBeginWork?.cancel()
        annotationBeginWork = nil
        if userAnnotationMode == .sticky, isUserAnnotating {
            finishCurrentUserAnnotationMode(logReason: "sticky")
        } else {
            startStickyUserAnnotationMode()
        }
    }

    private func startStickyUserAnnotationMode() {
        guard !isTurnRunning,
              !isVoiceCaptureActive,
              !isOnboardingActive
        else {
            return
        }
        if isClippyHidden {
            showClippy()
        }
        if isUserAnnotating {
            userAnnotationController?.cancel()
        }
        userAnnotationMode = .sticky
        isUserAnnotating = true
        pendingIdle?.cancel()
        overlay?.clear()
        let controller = userAnnotationController ?? UserAnnotationController()
        userAnnotationController = controller
        controller.begin(
            existing: userAnnotation,
            showsToolbar: true,
            toolbarActions: UserAnnotationToolbarActions(
                done: { [weak self] in self?.finishCurrentUserAnnotationMode(logReason: "sticky") },
                clear: { [weak self] in self?.clearStickyUserAnnotationMode() },
                cancel: { [weak self] in self?.cancelUserAnnotationMode() }
            )
        )
        syncBubbleAnchorToClippy()
        chatBubble?.showStatus("Annotation mode. Draw, then click Done.")
        _ = playOnce("GetAttention")
        log("user-annotation: sticky-begin")
    }

    private func finishCurrentUserAnnotationMode(logReason: String) {
        guard isUserAnnotating else { return }
        isUserAnnotating = false
        userAnnotationMode = nil
        guard let annotation = userAnnotationController?.finish(), !annotation.isEmpty else {
            userAnnotation = nil
            userAnnotationController?.cancel()
            overlay?.clear()
            syncBubbleAnchorToClippy()
            chatBubble?.showReplyForReading("No marks yet.")
            log("user-annotation: \(logReason)-empty")
            return
        }
        userAnnotation = annotation
        showUserAnnotationOverlay()
        syncBubbleAnchorToClippy()
        chatBubble?.showReplyForReading("Marked. Ask me what you want to know.")
        _ = playOnce("Explain")
        log("user-annotation: \(logReason)-finish strokes=\(annotation.strokes.count) screen=\(annotation.screenIndex + 1)")
    }

    private func clearStickyUserAnnotationMode() {
        guard userAnnotationMode == .sticky, isUserAnnotating else { return }
        userAnnotation = nil
        userAnnotationController?.clear()
        overlay?.clear()
        syncBubbleAnchorToClippy()
        chatBubble?.showStatus("Cleared. Draw again, then click Done.")
        log("user-annotation: sticky-clear")
    }

    @discardableResult
    private func clearScreenMarks(reason: String, includeUserAnnotation: Bool) -> Bool {
        let hasUserAnnotation = isUserAnnotating || userAnnotation != nil || isAnnotationHoldActive
        let hasAssistantOverlay = overlay?.hasContent == true && (!hasUserAnnotation || includeUserAnnotation)
        let hasGuidedTarget = guidedTarget != nil
        guard hasAssistantOverlay || hasGuidedTarget || (includeUserAnnotation && hasUserAnnotation) else {
            return false
        }

        disarmGuidedTarget(reason: reason)
        if includeUserAnnotation {
            isAnnotationHoldActive = false
            annotationBeginWork?.cancel()
            annotationBeginWork = nil
            isUserAnnotating = false
            userAnnotationMode = nil
            userAnnotation = nil
            userAnnotationController?.cancel()
        }
        overlay?.clear()
        syncBubbleAnchorToClippy()
        log("screen-marks: clear reason=\(reason) includeUserAnnotation=\(includeUserAnnotation)")
        return true
    }

    private func cancelUserAnnotationMode() {
        isAnnotationHoldActive = false
        annotationBeginWork?.cancel()
        annotationBeginWork = nil
        guard isUserAnnotating else {
            userAnnotationMode = nil
            userAnnotationController?.cancel()
            return
        }
        isUserAnnotating = false
        userAnnotationMode = nil
        userAnnotationController?.cancel()
        showUserAnnotationOverlay()
        log("user-annotation: cancel")
    }

    private func showUserAnnotationOverlay() {
        guard let annotation = userAnnotation, !annotation.isEmpty else {
            overlay?.clear()
            return
        }
        let screen = screen(forUserAnnotation: annotation)
        overlay?.show(annotation.scene, on: screen)
    }

    private func screen(forUserAnnotation annotation: UserScreenAnnotation) -> NSScreen? {
        if NSScreen.screens.indices.contains(annotation.screenIndex) {
            let indexed = NSScreen.screens[annotation.screenIndex]
            if indexed.frame == annotation.screenFrame {
                return indexed
            }
        }
        return NSScreen.screens.first { $0.frame == annotation.screenFrame }
            ?? (NSScreen.screens.indices.contains(annotation.screenIndex) ? NSScreen.screens[annotation.screenIndex] : nil)
    }

    private func showAnnotationHint() {
        cancelUserAnnotationMode()
        if isClippyHidden {
            showClippy()
        }
        syncBubbleAnchorToClippy()
        chatBubble?.showReplyForReading("Double-tap Control for annotation mode, or hold Control for a quick mark.")
        _ = playOnce("GetAttention")
    }

    private func showTextInputBubble(prefilledText: String = "") {
        guard let clippy, let chatBubble else {
            return
        }
        if isClippyHidden {
            showClippy()
        }
        chatBubble.setAnchor(clippy.frame)
        if chatBubble.isInputMode {
            if prefilledText.isEmpty == false {
                chatBubble.openInput(prefilledText: prefilledText)
                return
            }
            chatBubble.focusInput()
            return
        }
        clippy.play(clippy.spec.openInputAnimationName) { [weak clippy] _, state in
            if state == .waiting {
                clippy?.exitCurrentAnimation()
            }
        }
        chatBubble.openInput(prefilledText: prefilledText)
    }

    private func handleSubmittedText(_ text: String) {
        sendMessage(text)
    }

    private func sendMessage(
        _ text: String,
        inputMode: AssistantInputMode = .text,
        forcedModel: ClippyModel? = nil,
        initialThinkingStatus: String? = nil,
        visibleUserLine: String? = nil
    ) {
        guard let chatBubble else {
            return
        }
        if isTurnRunning {
            log("turn interrupted by follow-up")
            interruptSpeechAndResponse()
        }
        let forceSelectedProvider = forcedModel != nil
        let needsToolLane = ClippyAgentInstructions.shouldUseCodexToolLane(text: text, inputMode: inputMode)
        let needsComputerControl = ClippyAgentInstructions.shouldUseComputerControl(text: text, inputMode: inputMode)
        let needsVisualGrounding = ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: text, inputMode: inputMode)
        let toolLaneBrain = (!forceSelectedProvider && needsToolLane) ? computerControlBrain() : nil
        let activeBrain = toolLaneBrain ?? conversation
        let attemptedModel = forcedModel ?? (toolLaneBrain == nil ? selectedModel : .gpt55)
        guard let activeBrain else {
            log("brain unavailable for message: \(text.prefix(120))")
            if isClippyHidden == false {
                syncBubbleAnchorToClippy()
                chatBubble.showReplyForReading("(My local brain isn't installed.)")
            }
            return
        }
        isTurnRunning = true
        activeTurnUsedUserAnnotation = false
        turnHasStreamingText = false
        streamingReplySegmentID = nil
        cancelSpokenBubbleHide()
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        cancelTurnProgressUpdates()
        pendingIdle?.cancel()
        log("user: \(text)")
        activeUserRequest = ActiveUserRequest(text: text, inputMode: inputMode, attemptedModel: attemptedModel)
        turnGeneration += 1
        let turnID = turnGeneration
        guidedCompletedSteps = []
        nextGuidedTargetRound = 0

        let brain = activeBrain
        if needsComputerControl {
            log("routing: codex computer-control requested")
        }
        let desktopContext = DesktopContextSnapshot.capture()
        lastDesktopContext = desktopContext
        log("desktop-context: \(desktopContext.logSummary)")
        // Give Clippy eyes on every turn so short phrases like "do this" and
        // typed bubble turns still carry the real app/window context underneath.
        let wantsScreen = ClippyAgentInstructions.shouldAttachScreenshot(
            text: text,
            inputMode: inputMode,
            desktopContext: desktopContext
        )
        let screenshotScreen = desktopContext.targetScreen() ?? screenForClippy()
        let shots = wantsScreen ? captureTurnScreenshots(primaryScreen: screenshotScreen) : []
        let shot = primaryShot(in: shots, primaryScreen: screenshotScreen)
        lastShots = shots
        lastShot = shot
        if shots.isEmpty == false {
            logScreenCaptures(shots, primary: shot)
        } else if wantsScreen {
            log("screen-capture: unavailable")
        } else {
            log("screen-capture: skipped")
        }
        let userAnnotationContext = userAnnotation?.promptBlock(for: shots)
        activeTurnUsedUserAnnotation = userAnnotationContext != nil
        if isClippyHidden == false {
            syncBubbleAnchorToClippy()
            let userLine = visibleUserLine ?? text
            if userLine.isEmpty == false {
                chatBubble.recordUserLine(userLine)
            }
            chatBubble.showThinking(initialThinkingStatus ?? (shot == nil ? "Starting the brain" : "Sending the screen"))
        }
        scheduleTurnProgressUpdates(wantsScreen: wantsScreen, attachedScreenshot: shot != nil)
        playActivityState(.thinking)
        let screenshotContexts = Self.screenshotPromptContexts(for: shots, primary: shot)
        let visualGroundingContext = needsVisualGrounding
            ? VisualGroundingContext(
                originalUserText: text,
                screenshotPath: shot?.path,
                screenshotPixelWidth: Int(shot?.pixelSize.width ?? 0),
                screenshotPixelHeight: Int(shot?.pixelSize.height ?? 0),
                screenshots: screenshotContexts,
                desktopContext: desktopContext
            )
            : nil
        // Tell the brain how this turn arrives and leaves: spoken-and-transcribed input
        // (read past STT typos) and/or spoken output (write for the ear).
        let speaking = ttsEnabled && ClippySecrets.xaiAPIKey != nil
        let brainMessage = ClippyAgentInstructions.brainMessage(
            text: text,
            screenshotPath: shot?.path,
            screenshotPixelWidth: Int(shot?.pixelSize.width ?? 0),
            screenshotPixelHeight: Int(shot?.pixelSize.height ?? 0),
            screenshots: screenshotContexts,
            inputMode: inputMode,
            speaking: speaking,
            desktopContext: desktopContext,
            requiresVisualGrounding: needsVisualGrounding,
            userAnnotationContext: userAnnotationContext)
        ttsSpokenChars = 0
        let localImagePaths = Self.localImagePaths(for: shots)
        currentBrainTask = Task { [weak self] in
            for await chunk in brain.stream(brainMessage, localImagePaths: localImagePaths) {
                if Task.isCancelled { break }
                await MainActor.run { [weak self] in
                    guard let self, self.turnGeneration == turnID else {
                        return
                    }
                    switch chunk {
                    case .status(let status):
                        self.showTurnProgress(status)
                    case .partial(let partial):
                        self.handleStreamingPartial(partial, segmentID: nil)
                    case .partialMessage(let partial, let id):
                        self.handleStreamingPartial(partial, segmentID: id)
                    case .final(let turn):
                        self.receiveReply(
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
        let screenStatus = attachedScreenshot ? "Reading the screen" : "Thinking"
        let phases: [(TimeInterval, String)] = [
            (1.0, wantsScreen ? screenStatus : "Thinking"),
            (3.0, "Still thinking"),
            (6.0, "Still working"),
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

    private func cancelTurnTimeout() {
        // Clippy does not impose a local deadline on model turns. Provider errors
        // and user interruption still end the turn through the normal paths.
    }

    private func captureTurnScreenshot(screen targetScreen: NSScreen?) -> ScreenPerception.Screenshot? {
        let clippyWindow = clippy?.windowController.window
        let belowWindowNumber = clippyWindow?.isVisible == true ? clippyWindow?.windowNumber : nil

        overlay?.clear()
        let shot = ScreenPerception.captureToFile(screen: targetScreen, belowWindowNumber: belowWindowNumber)
        showUserAnnotationOverlay()
        return shot
    }

    private func captureTurnScreenshots(primaryScreen targetScreen: NSScreen?) -> [ScreenPerception.Screenshot] {
        let clippyWindow = clippy?.windowController.window
        let belowWindowNumber = clippyWindow?.isVisible == true ? clippyWindow?.windowNumber : nil

        overlay?.clear()
        let shots = ScreenPerception.captureAllToFiles(belowWindowNumber: belowWindowNumber)
        if shots.isEmpty == false {
            showUserAnnotationOverlay()
            return shots
        }
        let fallback = ScreenPerception.captureToFile(screen: targetScreen, belowWindowNumber: belowWindowNumber).map { [$0] } ?? []
        showUserAnnotationOverlay()
        return fallback
    }

    private func primaryShot(
        in shots: [ScreenPerception.Screenshot],
        primaryScreen targetScreen: NSScreen?
    ) -> ScreenPerception.Screenshot? {
        guard shots.isEmpty == false else { return nil }
        if let targetScreen,
           let matchingFrame = shots.first(where: { $0.screenFrame == targetScreen.frame }) {
            return matchingFrame
        }
        if let targetScreen,
           let screenIndex = NSScreen.screens.firstIndex(where: { $0 === targetScreen || $0.frame == targetScreen.frame }),
           let matchingIndex = shots.first(where: { $0.screenIndex == screenIndex }) {
            return matchingIndex
        }
        if let mainFrame = NSScreen.main?.frame,
           let main = shots.first(where: { $0.screenFrame == mainFrame }) {
            return main
        }
        return shots.first
    }

    private func logScreenCaptures(
        _ shots: [ScreenPerception.Screenshot],
        primary: ScreenPerception.Screenshot?
    ) {
        let primaryIndex = primary?.screenIndex
        for shot in shots {
            let marker = shot.screenIndex == primaryIndex ? " primary" : ""
            log("screen-capture: index=\(shot.screenIndex)\(marker) frame=\(shot.screenFrame) pixels=\(Int(shot.pixelSize.width))x\(Int(shot.pixelSize.height))")
        }
    }

    private static func localImagePaths(for screenshot: ScreenPerception.Screenshot?) -> [String] {
        localImagePaths(for: screenshot?.path)
    }

    private static func localImagePaths(for screenshots: [ScreenPerception.Screenshot]) -> [String] {
        screenshots.map(\.path).filter { $0.isEmpty == false }
    }

    private static func localImagePaths(for path: String?) -> [String] {
        guard let path, !path.isEmpty else { return [] }
        return [path]
    }

    private static func screenshotPromptContexts(
        for screenshots: [ScreenPerception.Screenshot],
        primary: ScreenPerception.Screenshot?
    ) -> [ClippyAgentInstructions.ScreenshotPromptContext] {
        screenshots.map { shot in
            ClippyAgentInstructions.ScreenshotPromptContext(
                path: shot.path,
                pixelWidth: Int(shot.pixelSize.width),
                pixelHeight: Int(shot.pixelSize.height),
                screenNumber: shot.screenIndex + 1,
                isPrimary: shot.screenIndex == primary?.screenIndex && shot.screenFrame == primary?.screenFrame
            )
        }
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
        guard let tts = activeTTS() else { return }
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
        turnGeneration += 1
        currentBrainTask?.cancel()
        currentBrainTask = nil
        tts?.stop()
        cancelSpokenBubbleHide()
        cancelTurnProgressUpdates()
        cancelTurnTimeout()
        isVoiceCaptureActive = false
        activeTurnUsedUserAnnotation = false
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        turnHasStreamingText = false
        streamingReplySegmentID = nil
        isTurnRunning = false
    }

    @objc private func stopTalking() {
        interruptSpeechAndResponse()
        overlay?.clear()
        userAnnotation = nil
        chatBubble?.hide()
        scheduleNextIdle()
    }


    private func handleStreamingPartial(_ text: String, segmentID: String?) {
        if let segmentID, streamingReplySegmentID != segmentID {
            streamingReplySegmentID = segmentID
            ttsSpokenChars = 0
            turnHasStreamingText = false
        }
        showStreamingReply(text)
        speakStreaming(text, final: false)
    }

    /// Live partial text while the reply streams in. Tags (even half-typed) are
    /// stripped before display so a bracket never flashes in the bubble.
    private func showStreamingReply(_ text: String) {
        guard isClippyHidden == false else { return }
        if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
        let display = ClippyUserFacingError.replacement(for: text, isError: false)
            ?? VoiceSpeechTags.stripForStreaming(GroundingParser.stripForStreaming(text))
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
        streamingReplySegmentID = nil
        isTurnRunning = false
        if isClippyHidden {
            log("clippy: \(turn.text.prefix(120))")
            return
        }
        if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
        if offerProviderFallbackIfAvailable(turn.text) {
            log("clippy: \(turn.text.prefix(120))")
            return
        }
        let friendlyFailure = ClippyUserFacingError.replacement(for: turn.text, isError: turn.isError)
        let replyText = friendlyFailure ?? turn.text
        let parsed = GroundingParser.parse(replyText)
        let visualTags = parsed.tags.filter(\.isRenderableVisual)
        if visualGroundingContext != nil {
            log("visual-grounding-tags: renderable=\(visualTags.count) total=\(parsed.tags.count)")
        }
        if shouldRepairVisualGrounding(turn: turn, parsed: parsed, context: visualGroundingContext) {
            repairVisualGrounding(context: visualGroundingContext!, previousTurn: turn, brain: brain)
            return
        }
        if activeTurnUsedUserAnnotation, turn.isError == false {
            userAnnotation = nil
            activeTurnUsedUserAnnotation = false
        }
        // Runtime failures get a Clippy-shaped sentence; normal replies show only
        // the stripped speech. A tag-only reply shows nothing — never raw brackets.
        let spoken = VoiceSpeechTags.strip(parsed.spokenText)
        let replyTTS = turn.isError ? nil : activeTTS()
        if spoken.isEmpty {
            chatBubble?.hide()
        } else if replyTTS != nil {
            showSpokenReplyBubble(spoken)
        } else {
            chatBubble?.showReplyForReading(spoken)
        }
        // Flush any sentence not yet spoken. Streamed replies already spoke most of it
        // sentence-by-sentence; any non-streaming fallback speaks the whole reply here.
        if turn.isError == false {
            speakStreaming(replyText, final: true)
        }
        if replyTTS?.isSpeaking == false {
            scheduleSpokenBubbleHideAfterSpeech()
        }
        log("clippy: \(turn.text.prefix(120))")

        if !turn.isError, !visualTags.isEmpty {
            presentGrounding(visualTags, instructionText: spoken)
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

    private func offerProviderFallbackIfAvailable(_ text: String) -> Bool {
        guard let activeUserRequest,
              let offer = BrainFallbackPolicy.offer(
            afterProviderIssueText: text,
            attemptedModel: activeUserRequest.attemptedModel,
            isChatGPTAvailable: BrainDiscovery.codexSignedIn(),
            isClaudeAvailable: BrainDiscovery.claudeSignedIn()
        )
        else {
            return false
        }
        showProviderFallbackChoice(offer, retrying: activeUserRequest)
        return true
    }

    private func showProviderFallbackChoice(_ offer: BrainFallbackOffer, retrying request: ActiveUserRequest) {
        overlay?.clear()
        playActivityState(.attention)
        chatBubble?.showChoicesTyping(offer.prompt, choices: [
            .init(title: offer.actionTitle) { [weak self] in
                self?.selectProviderAfterIssue(offer, retrying: request)
            },
            .init(title: offer.keepTitle) { [weak self] in
                self?.keepProviderAfterIssue(offer, retrying: request)
            },
            .init(title: offer.discardTitle) { [weak self] in
                self?.discardProviderIssue(offer)
            },
        ])
        let animationName = clippy?.spec.replyAnimationName ?? "Explain"
        clippy?.play(animationName) { [weak self, weak clippy] _, state in
            switch state {
            case .waiting:
                clippy?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    private func selectProviderAfterIssue(_ offer: BrainFallbackOffer, retrying request: ActiveUserRequest) {
        applySelectedModel(offer.toModel)
        log("model selected: \(offer.toModel.id) after \(offer.fromProviderName) provider fallback; retrying")
        if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
        sendMessage(
            request.text,
            inputMode: request.inputMode,
            forcedModel: offer.toModel,
            initialThinkingStatus: "Switched to \(offer.toProviderName). Trying again"
        )
    }

    private func keepProviderAfterIssue(_ offer: BrainFallbackOffer, retrying request: ActiveUserRequest) {
        guard offer.reason == .connection else {
            activeUserRequest = nil
            chatBubble?.showReplyForReading("Still on \(offer.fromProviderName).")
            return
        }
        log("model retry: \(offer.fromProviderName) after timeout")
        if let frame = clippy?.frame { chatBubble?.setAnchor(frame) }
        sendMessage(
            request.text,
            inputMode: request.inputMode,
            initialThinkingStatus: "Trying \(offer.fromProviderName) again"
        )
    }

    private func discardProviderIssue(_ offer: BrainFallbackOffer) {
        activeUserRequest = nil
        overlay?.clear()
        syncBubbleAnchorToClippy()
        chatBubble?.showReplyForReading("Discarded.")
        log("model fallback: discarded \(offer.fromProviderName) \(offer.reason)")
    }

    private func shouldRepairVisualGrounding(
        turn: AgentTurn,
        parsed: GroundingDirectives,
        context: VisualGroundingContext?
    ) -> Bool {
        guard context != nil, turn.isError == false else { return false }
        return parsed.tags.contains(where: \.isRenderableVisual) == false
    }

    private func pointTagCount(in tags: [GroundingTag]) -> Int {
        tags.reduce(0) { count, tag in
            if case .point = tag { return count + 1 }
            return count
        }
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
        chatBubble?.showThinking("Finding the spot")
        playActivityState(.thinking)
        let repairMessage = ClippyAgentInstructions.visualGroundingRepairMessage(
            originalUserText: context.originalUserText,
            previousAssistantText: previousTurn.text,
            screenshotPath: context.screenshotPath,
            screenshotPixelWidth: context.screenshotPixelWidth,
            screenshotPixelHeight: context.screenshotPixelHeight,
            screenshots: context.screenshots,
            desktopContext: context.desktopContext
        )
        let localImagePaths = context.screenshots.map(\.path).filter { $0.isEmpty == false }
        currentBrainTask = Task { [weak self] in
            let repairTurn = await brain.send(
                repairMessage,
                localImagePaths: localImagePaths
            )
            if Task.isCancelled { return }
            await MainActor.run {
                self?.receiveReply(repairTurn)
            }
        }
    }

    /// Render parsed grounding directives: draw the marks, and move Clippy beside the
    /// first anchored target so it points at it with the matching body gesture.
    private func presentGrounding(_ rawTags: [GroundingTag], instructionText: String? = nil) {
        guard isClippyHidden == false else {
            return
        }
        let fallbackScreen = screenForClippy() ?? NSScreen.main ?? NSScreen.screens.first
        let screen = screenForGrounding(rawTags) ?? screenForLastShot() ?? fallbackScreen
        guard let screen else { return }
        // The model emitted coordinates in the screenshot's pixel space; map them onto
        // the actual screen so the ring and Clippy's body land in the right place.
        let tags = rawTags.map { tag -> GroundingTag in
            guard let shot = screenshot(for: tag) else { return tag }
            return tag.inScreenSpace(imageSize: shot.pixelSize, display: shot.screenFrame)
        }
        log("grounding-presented: points=\(pointTagCount(in: tags)) total=\(tags.count)")
        log("grounding-beats: \(groundingBeatSummary(tags))")
        let marks = tags.compactMap(AnnotationMark.init(tag:))
        let scene = groundingScene(from: marks)
        overlay?.showSequence(scene, on: screen)
        armGuidedTarget(from: tags, instructionText: instructionText)
        if let anchor = scene.primaryPoint(windowFrameProvider: { $0.currentFrame() ?? $0.initialFrame })
            ?? tags.first(where: { $0.anchor != nil })?.anchor {
            // Point at a target with Clippy's body.
            moveClippyToPoint(at: anchor, in: screen)
        } else if let animation = firstActAnimation(in: tags) {
            // Emote: Clippy performs the animation it asked for, in place.
            pendingIdle?.cancel()
            if playOnce(animation) == false {
                log("unknown animation requested: \(animation)")
                scheduleNextIdle()
            }
        }
    }

    private func moveClippyToPoint(at anchor: CGPoint, in screen: NSScreen) {
        guard let clippy else { return }
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
    }

    private func screenshot(for tag: GroundingTag) -> ScreenPerception.Screenshot? {
        if let screenNumber = tag.screenNumber {
            return lastShots.first { $0.screenIndex + 1 == screenNumber }
        }
        return lastShot ?? lastShots.first
    }

    private func screenForGrounding(_ tags: [GroundingTag]) -> NSScreen? {
        for tag in tags {
            guard let shot = screenshot(for: tag),
                  let screen = screen(for: shot) else { continue }
            return screen
        }
        return nil
    }

    private func groundingScene(from marks: [AnnotationMark]) -> DrawingScene {
        guard !marks.isEmpty,
              lastShot != nil,
              let context = lastDesktopContext,
              let anchor = DrawingWindowAnchor(desktopContext: context) else {
            return DrawingScene(marks: marks)
        }
        return DrawingScene(marks: marks, anchor: .window(anchor))
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

    private func armGuidedTarget(from tags: [GroundingTag], instructionText: String?) {
        let round = nextGuidedTargetRound
        nextGuidedTargetRound = 0
        guard let target = firstGuidedTarget(in: tags, round: round, instructionText: instructionText) else {
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
            self.overlay?.clear()
        }
        guidedTargetExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: expiry)
    }

    private func firstGuidedTarget(in tags: [GroundingTag], round: Int, instructionText: String?) -> GuidedTarget? {
        let goal = activeUserRequest?.text ?? ""
        let instruction = instructionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for tag in tags {
            switch tag {
            case let .target(center, radius, label, _):
                return GuidedTarget(
                    kind: .click,
                    center: center,
                    radius: CGFloat(radius),
                    label: label,
                    round: round,
                    overallGoal: goal,
                    previousInstruction: instruction
                )
            case let .hover(center, radius, label, _):
                return GuidedTarget(
                    kind: .hover,
                    center: center,
                    radius: CGFloat(radius),
                    label: label,
                    round: round,
                    overallGoal: goal,
                    previousInstruction: instruction
                )
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
        if !guidedCompletedSteps.contains(target.label) {
            guidedCompletedSteps.append(target.label)
        }
        nextGuidedTargetRound = nextRound
        log("guided target follow-up start label=\(target.label) round=\(nextRound) \(trigger)X=\(Int(point.x)) \(trigger)Y=\(Int(point.y))")

        let desktopContext = DesktopContextSnapshot.capture()
        lastDesktopContext = desktopContext
        log("desktop-context: \(desktopContext.logSummary)")
        let screenshotScreen = desktopContext.targetScreen() ?? screenForClippy()
        let shots = captureTurnScreenshots(primaryScreen: screenshotScreen)
        let shot = primaryShot(in: shots, primaryScreen: screenshotScreen)
        lastShots = shots
        lastShot = shot
        if shots.isEmpty == false {
            logScreenCaptures(shots, primary: shot)
        } else {
            log("screen-capture: unavailable")
        }

        if isClippyHidden == false {
            syncBubbleAnchorToClippy()
            chatBubble?.showThinking("Checking that step")
        }
        scheduleTurnProgressUpdates(wantsScreen: true, attachedScreenshot: shot != nil)
        playActivityState(.thinking)

        let message = ClippyAgentInstructions.guidedTargetFollowUpMessage(
            label: target.label,
            trigger: trigger,
            triggerPointX: Int(point.x),
            triggerPointY: Int(point.y),
            round: nextRound,
            remainingRounds: remainingRounds,
            overallGoal: target.overallGoal,
            previousInstruction: target.previousInstruction,
            completedSteps: guidedCompletedSteps,
            screenshotPath: shot?.path,
            screenshotPixelWidth: Int(shot?.pixelSize.width ?? 0),
            screenshotPixelHeight: Int(shot?.pixelSize.height ?? 0),
            screenshots: Self.screenshotPromptContexts(for: shots, primary: shot),
            desktopContext: desktopContext
        )
        let localImagePaths = Self.localImagePaths(for: shots)
        currentBrainTask = Task { [weak self] in
            for await chunk in brain.stream(message, localImagePaths: localImagePaths) {
                if Task.isCancelled { break }
                await MainActor.run {
                    switch chunk {
                    case .status(let status):
                        self?.showTurnProgress(status)
	                    case .partial(let partial):
	                        self?.handleStreamingPartial(partial, segmentID: nil)
	                    case .partialMessage(let partial, let id):
	                        self?.handleStreamingPartial(partial, segmentID: id)
	                    case .final(let turn):
	                        self?.receiveReply(turn)
                    }
                }
            }
        }
    }

    private func screenForLastShot() -> NSScreen? {
        guard let shot = lastShot else { return nil }
        return screen(for: shot)
    }

    private func screen(for shot: ScreenPerception.Screenshot) -> NSScreen? {
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
        cancelUserAnnotationMode()
        chatBubble?.hide()
        overlay?.clear()
        userAnnotation = nil
        permissionDrag?.hide()
        deepgramSTT?.cancel()
        usingDeepgram = false
        isVoiceCaptureActive = false
        voicePartialText = ""
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        cancelSpokenBubbleHide()
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
        items.append(.action("Annotate Screen", detail: "Ctrl Ctrl") { [weak self] in
            self?.startStickyUserAnnotationMode()
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
            RetroMenuItem.choice(voice.displayName, detail: voice.detail, isSelected: voice.id == selectedVoice.id) { [weak self] in
                self?.selectVoice(id: voice.id)
            }
        }
        items.append(.submenu("Voice", detail: selectedVoice.detail, items: voiceItems))

        items.append(.separator())
        items.append(.action("Setup...") { [weak self] in
            self?.startBubbleOnboarding(force: true)
        })
        items.append(.action("Configure API Key...") { [weak self] in
            self?.showProviderKeys()
        })
        items.append(.action("Check for Updates...") { [weak self] in
            self?.checkForUpdates()
        })

        let permissionItems: [RetroMenuItem] = [
            .toggle("Accessibility", isOn: AccessibilityPermission.isTrusted) { [weak self] in
                self?.grantAccessibility()
            },
            .toggle("Screen Recording", isOn: ScreenPerception.hasPermission) { [weak self] in
                self?.grantScreenRecording()
            },
            .toggle("Full Disk Access", isOn: FullDiskAccessPermission.isGranted) { [weak self] in
                self?.grantFullDiskAccess()
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
        if sttEnabled {
            if ptt == nil {
                setUpVoice()
            }
        } else {
            let wasCapturing = isVoiceCaptureActive
            isVoiceCaptureActive = false
            usingDeepgram = false
            deepgramSTT?.cancel()
            if wasCapturing {
                _ = speech?.stop()
            }
            ptt?.stop()
            ptt = nil
        }
    }

    @objc private func toggleTTS() {
        ttsEnabled.toggle()
        UserDefaults.standard.set(ttsEnabled, forKey: "ClippyTTSEnabled")
        if !ttsEnabled {
            hideBubbleWhenSpeechFinishes = false
            spokenBubbleShownAt = nil
            cancelSpokenBubbleHide()
            tts?.stop()
        }
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
        showPermissionDialog(permission: .accessibility)
    }

    @objc private func grantScreenRecording() {
        _ = ScreenPerception.requestPermission()
        showPermissionDialog(permission: .screenRecording)
    }

    @objc private func grantFullDiskAccess() {
        showPermissionDialog(permission: .fullDiskAccess)
    }

    @objc private func grantMicrophone() {
        Task { _ = await SpeechCapture.requestMicrophone() }
        showPermissionDialog(permission: .microphone)
    }

    @objc private func openProviderKeys() {
        showProviderKeys()
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    private func showProviderKeys() {
        if providerKeys == nil {
            providerKeys = ProviderKeysController { [weak self] in
                self?.configureVoiceProviders()
                if self?.isOnboardingActive == true {
                    self?.showAPIKeyOnboarding()
                }
            }
        }
        providerKeys?.showWindow(nil)
    }

    private func showInitialSetupIfNeeded() {
        let setupCompleted = UserDefaults.standard.bool(forKey: Self.setupCompletedKey)
        let shouldShowSetup = !setupCompleted || !BrainDiscovery.anyBrainSignedIn()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if shouldShowSetup {
                self.startBubbleOnboarding(force: false)
            } else if !ClippySecrets.missingRequiredProviderNames.isEmpty {
                self.setUpBrain()
                self.showAPIKeyOnboarding()
            } else {
                self.setUpBrain()
            }
        }
    }

    private func markSetupCompleted() {
        UserDefaults.standard.set(true, forKey: Self.setupCompletedKey)
        clearOnboardingResumePoint()
    }

    private func startBubbleOnboarding(force: Bool) {
        if isClippyHidden {
            showClippy()
        }
        cancelOnboardingDemoWork()
        cancelSpokenBubbleHide()
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        onboardingPermissionsRequested.removeAll()
        isOnboardingActive = true
        syncBubbleAnchorToClippy()
        if force {
            clearOnboardingResumePoint()
            showWelcomeStep()
        } else {
            resumeBubbleOnboarding()
        }
    }

    private func saveOnboardingResumePoint(_ point: ClippyOnboardingResumePoint) {
        UserDefaults.standard.set(point.rawValue, forKey: ClippyOnboardingResumePoint.defaultsKey)
    }

    private func clearOnboardingResumePoint() {
        UserDefaults.standard.removeObject(forKey: ClippyOnboardingResumePoint.defaultsKey)
    }

    private func savedOnboardingResumePoint() -> ClippyOnboardingResumePoint {
        ClippyOnboardingResumePoint.savedPoint(
            from: UserDefaults.standard.string(forKey: ClippyOnboardingResumePoint.defaultsKey)
        )
    }

    private func resumeBubbleOnboarding() {
        switch savedOnboardingResumePoint() {
        case .welcome:
            showWelcomeStep()
        case .brainChoice:
            showBrainChoiceStep()
        case .brainHelp:
            showBrainHelpStep()
        case .chatGPT:
            showCodexOnboarding()
        case .claude:
            showClaudeOnboarding()
        case .listening:
            showListeningStep()
        case .voice:
            showVoiceStep()
        case .screenHelp:
            showScreenHelpStep()
        case .fileAccess:
            showFileAccessStep()
        case .demo:
            startOnboardingDemo()
        case .controls:
            showOnboardingControlsStep(createdPageURL: nil)
        }
    }

    private func showWelcomeStep() {
        saveOnboardingResumePoint(.welcome)
        showOnboardingStep(
            "Hi, I'm Clippy, your new desktop buddy. Let's get me set up — it's quick.",
            animation: "Greeting",
            choices: [
                .init(title: "Let's go") { [weak self] in self?.showBrainChoiceStep() },
            ]
        )
    }

    private func showBrainChoiceStep() {
        saveOnboardingResumePoint(.brainChoice)
        showOnboardingStep(
            "First, I need a brain to think with. ChatGPT or Claude — either one's great.",
            animation: "GetAttention",
            choices: [
                .init(title: "ChatGPT") { [weak self] in self?.showCodexOnboarding() },
                .init(title: "Claude") { [weak self] in self?.showClaudeOnboarding() },
                .init(title: "Help me pick") { [weak self] in self?.showBrainHelpStep() },
            ]
        )
    }

    private func showBrainHelpStep() {
        saveOnboardingResumePoint(.brainHelp)
        let codex = BrainDiscovery.codexStatus()
        let claude = BrainDiscovery.claudeStatus()
        let prompt = """
        Let me see what you've got here.
        ChatGPT: \(codex.statusText)
        Claude: \(claude.statusText)
        Pick whichever, and I'll run with it.
        """
        showOnboardingStep(prompt, animation: "CheckingSomething", choices: [
            .init(title: "ChatGPT") { [weak self] in self?.showCodexOnboarding() },
            .init(title: "Claude") { [weak self] in self?.showClaudeOnboarding() },
            .init(title: "Skip for now") { [weak self] in self?.showListeningStep() },
        ])
    }

    private func showCodexOnboarding() {
        saveOnboardingResumePoint(.chatGPT)
        let status = BrainDiscovery.codexStatus()
        if status.signedIn {
            showOnboardingStep(
                "Nice — ChatGPT's already signed in. I can use that.",
                animation: "GetTechy",
                choices: [
                    .init(title: "Use ChatGPT") { [weak self] in
                        self?.selectOnboardingModel(.gpt55)
                    },
                    .init(title: "Back") { [weak self] in self?.showBrainChoiceStep() },
                ]
            )
        } else if status.isInstalled {
            showOnboardingStep(
                "ChatGPT's here — just sign in and we're good.",
                animation: "GetTechy",
                choices: [
                    .init(title: "Sign in") { [weak self] in self?.runCodexLogin() },
                    .init(title: "Back") { [weak self] in self?.showBrainChoiceStep() },
                ]
            )
        } else {
            showOnboardingStep(
                "I don't see ChatGPT yet. Want me to grab it? Takes a sec.",
                animation: "GetTechy",
                choices: [
                    .init(title: "Set it up") { [weak self] in self?.runCodexInstall() },
                    .init(title: "Back") { [weak self] in self?.showBrainChoiceStep() },
                ]
            )
        }
    }

    private func showClaudeOnboarding() {
        saveOnboardingResumePoint(.claude)
        let status = BrainDiscovery.claudeStatus()
        if status.signedIn {
            showOnboardingStep(
                "Nice — Claude's already signed in. I can use that.",
                animation: "GetWizardy",
                choices: [
                    .init(title: "Use Claude") { [weak self] in
                        self?.selectOnboardingModel(.opus48)
                    },
                    .init(title: "Back") { [weak self] in self?.showBrainChoiceStep() },
                ]
            )
        } else if status.isInstalled {
            showOnboardingStep(
                "Claude's here — just sign in and we're good.",
                animation: "GetWizardy",
                choices: [
                    .init(title: "Sign in") { [weak self] in self?.runClaudePlanLogin() },
                    .init(title: "Back") { [weak self] in self?.showBrainChoiceStep() },
                ]
            )
        } else {
            showOnboardingStep(
                "I don't see Claude yet. Want me to grab it? Takes a sec.",
                animation: "GetWizardy",
                choices: [
                    .init(title: "Set it up") { [weak self] in self?.runClaudeInstall() },
                    .init(title: "Back") { [weak self] in self?.showBrainChoiceStep() },
                ]
            )
        }
    }

    // Listening (me hearing you) and my own voice (me talking back) are two different
    // things, so they get two separate steps: Deepgram powers my ears, xAI powers my mouth.
    private func showListeningStep() {
        saveOnboardingResumePoint(.listening)
        if ClippySecrets.deepgramAPIKey != nil {
            showOnboardingStep(
                "Wanna talk to me out loud instead of typing?",
                animation: "Hearing_1",
                choices: [
                    .init(title: "Sure") { [weak self] in self?.enableOnboardingListening() },
                    .init(title: "Maybe later") { [weak self] in self?.skipOnboardingListening() },
                ]
            )
        } else {
            showOnboardingStep(
                "To hear you, I need a quick voice key. Wanna add one?",
                animation: "Hearing_1",
                choices: [
                    .init(title: "Add a key") { [weak self] in self?.showProviderKeys() },
                    .init(title: "Maybe later") { [weak self] in self?.showVoiceStep() },
                ]
            )
        }
    }

    private func showVoiceStep() {
        saveOnboardingResumePoint(.voice)
        if ClippySecrets.xaiAPIKey != nil {
            showOnboardingStep(
                "Want me to talk back out loud, or keep it quiet?",
                animation: "Wave",
                choices: [
                    .init(title: "Out loud") { [weak self] in self?.enableOnboardingSpeech() },
                    .init(title: "Stay quiet") { [weak self] in self?.skipOnboardingSpeech() },
                ]
            )
        } else {
            showOnboardingStep(
                "To talk back out loud, I need a quick voice key. Add one?",
                animation: "Wave",
                choices: [
                    .init(title: "Add a key") { [weak self] in self?.showProviderKeys() },
                    .init(title: "Stay quiet") { [weak self] in self?.skipOnboardingSpeech() },
                ]
            )
        }
    }

    private func showAPIKeyOnboarding() {
        showListeningStep()
    }

    private func enableOnboardingListening() {
        sttEnabled = true
        UserDefaults.standard.set(true, forKey: "ClippySTTEnabled")
        configureVoiceProviders()
        if ptt == nil {
            setUpVoice()
        }
        guard !MicrophonePermission.isGranted else {
            showVoiceStep()
            return
        }
        syncBubbleAnchorToClippy()
        chatBubble?.showThinking("Asking for microphone")
        Task { [weak self] in
            let granted = await SpeechCapture.requestMicrophone()
            await MainActor.run {
                guard let self else { return }
                if granted {
                    self.showVoiceStep()
                } else {
                    self.showPermissionDialog(permission: .microphone, doneButtonTitle: "Done") { [weak self] in
                        self?.showVoiceStep()
                    }
                }
            }
        }
    }

    private func skipOnboardingListening() {
        sttEnabled = false
        UserDefaults.standard.set(false, forKey: "ClippySTTEnabled")
        if isVoiceCaptureActive {
            _ = speech?.stop()
        }
        isVoiceCaptureActive = false
        usingDeepgram = false
        deepgramSTT?.cancel()
        ptt?.stop()
        ptt = nil
        showVoiceStep()
    }

    private func enableOnboardingSpeech() {
        ttsEnabled = true
        UserDefaults.standard.set(true, forKey: "ClippyTTSEnabled")
        configureVoiceProviders()
        showScreenHelpStep()
    }

    private func skipOnboardingSpeech() {
        ttsEnabled = false
        UserDefaults.standard.set(false, forKey: "ClippyTTSEnabled")
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        cancelSpokenBubbleHide()
        tts?.stop()
        showScreenHelpStep()
    }

    private func showScreenHelpStep() {
        saveOnboardingResumePoint(.screenHelp)
        if AccessibilityPermission.isTrusted && ScreenPerception.hasPermission {
            showFileAccessStep()
            return
        }
        showOnboardingStep(
            "Want me to help with stuff on your screen? I only look when you ask — never in the background.",
            animation: "GetAttention",
            choices: [
                .init(title: "Yes, help out") { [weak self] in self?.requestScreenHelpPermissions() },
                .init(title: "Maybe later") { [weak self] in self?.showFileAccessStep() },
            ]
        )
    }

    private func requestScreenHelpPermissions() {
        saveOnboardingResumePoint(.screenHelp)
        let permissionOrder: [OnboardingPermission] = [.screenRecording, .accessibility]
        guard let permission = permissionOrder.first(where: {
            !$0.isGranted && !onboardingPermissionsRequested.contains($0)
        }) else {
            showFileAccessStep()
            return
        }
        onboardingPermissionsRequested.insert(permission)
        switch permission {
        case .accessibility:
            _ = AccessibilityPermission.requestIfNeeded(prompt: true)
        case .screenRecording:
            _ = ScreenPerception.requestPermission()
        case .fullDiskAccess, .microphone:
            return
        }
        showPermissionDialog(permission: permission, doneButtonTitle: "Done") { [weak self] in
            self?.requestScreenHelpPermissions()
        }
    }

    private func showFileAccessStep() {
        saveOnboardingResumePoint(.fileAccess)
        guard !FullDiskAccessPermission.isGranted else {
            startOnboardingDemo()
            return
        }
        showOnboardingStep(
            "Want me to dig through your apps when you ask — like finding an old text or a link you lost? Only when you ask.",
            animation: "Processing",
            choices: [
                .init(title: "Yeah, go ahead") { [weak self] in self?.requestFileAccessPermission() },
                .init(title: "Maybe later") { [weak self] in self?.startOnboardingDemo() },
            ]
        )
    }

    private func requestFileAccessPermission() {
        saveOnboardingResumePoint(.fileAccess)
        onboardingPermissionsRequested.insert(.fullDiskAccess)
        showPermissionDialog(permission: .fullDiskAccess, doneButtonTitle: "Done") { [weak self] in
            self?.startOnboardingDemo()
        }
    }

    private func selectOnboardingModel(_ model: ClippyModel) {
        applySelectedModel(model)
        log("model selected: \(model.id)")
        showListeningStep()
    }

    private func startOnboardingDemo() {
        saveOnboardingResumePoint(.demo)
        permissionDrag?.hide()
        cancelOnboardingDemoWork()
        overlay?.clear()
        if conversation == nil {
            setUpBrain()
        }
        if isClippyHidden {
            showClippy()
        }
        isOnboardingActive = true
        playOnboardingAnimation("GetAttention")
        syncBubbleAnchorToClippy()
        chatBubble?.showReplyForReading(ClippyOnboardingDemo.guidedIntroText)
        scheduleOnboardingDemoWork(after: 1.4) { [weak self] in
            self?.runOnboardingDemo()
        }
    }

    private func runOnboardingDemo() {
        guard isOnboardingActive else { return }
        cancelOnboardingDemoWork()
        overlay?.clear()
        syncBubbleAnchorToClippy()
        chatBubble?.showThinking(ClippyOnboardingDemo.guidedWorkingText)
        playActivityState(.working)

        scheduleOnboardingDemoWork(after: 0.8) { [weak self] in
            guard let self, self.isOnboardingActive else { return }
            self.log("onboarding-demo: current-screen prompt")
            self.playOnboardingAnimation("Explain")
            self.sendMessage(
                ClippyOnboardingDemo.demoRequestText,
                initialThinkingStatus: ClippyOnboardingDemo.guidedWorkingText,
                visibleUserLine: ClippyOnboardingDemo.visibleTaskLine
            )
            self.showOnboardingControlsWhenDemoSettles(createdPageURL: nil)
        }
    }

    private func showOnboardingControlsWhenDemoSettles(createdPageURL: URL?, attempt: Int = 0) {
        guard isOnboardingActive else { return }
        if isTurnRunning, attempt < 45 {
            scheduleOnboardingDemoWork(after: 2.0) { [weak self] in
                self?.showOnboardingControlsWhenDemoSettles(createdPageURL: createdPageURL, attempt: attempt + 1)
            }
            return
        }
        scheduleOnboardingDemoWork(after: overlay?.hasContent == true ? 5.0 : 1.5) { [weak self] in
            self?.showOnboardingControlsStep(createdPageURL: createdPageURL)
        }
    }

    private func showOnboardingControlsStep(createdPageURL: URL?) {
        guard isOnboardingActive else { return }
        saveOnboardingResumePoint(.controls)
        showOnboardingStep(
            ClippyOnboardingDemo.controlsText,
            animation: "GetAttention",
            choices: [
                .init(title: "Done") { [weak self] in
                    self?.completeBubbleOnboarding(createdPageURL: createdPageURL)
                },
            ]
        )
    }

    private func completeBubbleOnboarding(createdPageURL: URL?) {
        cancelOnboardingDemoWork()
        isOnboardingActive = false
        permissionDrag?.hide()
        if createdPageURL == nil {
            overlay?.clear()
        }
        markSetupCompleted()
        if conversation == nil {
            setUpBrain()
        }
        playOnboardingAnimation("Congratulate")
        chatBubble?.showReplyForReading("All set — I'm all yours! Press Control+Space to type, or hold Control+Option to talk.")
    }

    private func scheduleOnboardingDemoWork(after delay: TimeInterval, _ action: @escaping () -> Void) {
        let work = DispatchWorkItem(block: action)
        onboardingDemoWorkItems.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelOnboardingDemoWork() {
        onboardingDemoWorkItems.forEach { $0.cancel() }
        onboardingDemoWorkItems.removeAll()
    }

    private func voiceKeyStatusText() -> String {
        let missing = ClippySecrets.missingRequiredProviderNames
        return missing.isEmpty ? "Ready" : "Missing " + missing.joined(separator: ", ")
    }

    private func permissionStatusText() -> String {
        let permissions = [
            ("Accessibility", AccessibilityPermission.isTrusted),
            ("Screen Recording", ScreenPerception.hasPermission),
            ("Full Disk Access", FullDiskAccessPermission.isGranted),
            ("Microphone", MicrophonePermission.isGranted),
        ]
        let missing = permissions.filter { !$0.1 }.map(\.0)
        return missing.isEmpty ? "Ready" : "Missing " + missing.joined(separator: ", ")
    }

    private func runCodexLogin() {
        runSetupProcess(
            title: "ChatGPT Sign In",
            executablePath: CodexConversation.locateBinary() ?? "codex",
            arguments: ["login"],
            startMessage: "Popping open ChatGPT sign-in. Finish in your browser, then hit Refresh.",
            successMessage: "ChatGPT's signed in! Hit Refresh and we're good.",
            retry: { [weak self] in self?.runCodexLogin() },
            resume: { [weak self] in self?.showCodexOnboarding() }
        )
    }

    private func runCodexInstall() {
        if CodexConversation.locateBinary() != nil {
            runCodexLogin()
            return
        }
        runSetupShell(
            title: "Set Up ChatGPT",
            command: Self.codexInstallCommand(),
            startMessage: "Setting up ChatGPT for you — one sec.",
            successMessage: "ChatGPT's ready! Hit Refresh to sign in.",
            retry: { [weak self] in self?.runCodexInstall() },
            resume: { [weak self] in self?.showCodexOnboarding() }
        )
    }

    private func runClaudePlanLogin() {
        runSetupProcess(
            title: "Claude Sign In",
            executablePath: LocalCLIConversation.locateBinary() ?? "claude",
            arguments: ["auth", "login", "--claudeai"],
            startMessage: "Popping open Claude sign-in. Finish in your browser, then hit Refresh.",
            successMessage: "Claude's signed in! Hit Refresh and we're good.",
            retry: { [weak self] in self?.runClaudePlanLogin() },
            resume: { [weak self] in self?.showClaudeOnboarding() }
        )
    }

    private func runClaudeInstall() {
        if LocalCLIConversation.locateBinary() != nil {
            runClaudePlanLogin()
            return
        }
        runSetupShell(
            title: "Set Up Claude",
            command: Self.claudeInstallCommand(),
            startMessage: "Setting up Claude for you — one sec.",
            successMessage: "Claude's ready! Hit Refresh to sign in.",
            retry: { [weak self] in self?.runClaudeInstall() },
            resume: { [weak self] in self?.showClaudeOnboarding() }
        )
    }

    private func showOnboardingStep(
        _ prompt: String,
        animation: String = "Explain",
        choices: [ClippyBubbleController.Choice]
    ) {
        cancelSpokenBubbleHide()
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        syncBubbleAnchorToClippy()
        playOnboardingAnimation(animation)
        chatBubble?.showChoicesTyping(prompt, choices: choices)
    }

    private func playOnboardingAnimation(_ name: String) {
        pendingIdle?.cancel()
        guard isClippyHidden == false else {
            return
        }
        _ = playOnce(name)
    }

    private func runSetupShell(
        title: String,
        command: String,
        startMessage: String,
        successMessage: String,
        retry: @escaping () -> Void,
        resume: @escaping () -> Void
    ) {
        runSetupProcess(
            title: title,
            executablePath: "/bin/zsh",
            arguments: ["-lc", command],
            startMessage: startMessage,
            successMessage: successMessage,
            retry: retry,
            resume: resume
        )
    }

    private func runSetupProcess(
        title: String,
        executablePath: String,
        arguments: [String],
        startMessage: String,
        successMessage: String,
        retry: @escaping () -> Void,
        resume: @escaping () -> Void
    ) {
        cancelSetupProcess()
        let logURL: URL
        do {
            logURL = try Self.setupLogURL(title: title)
            let commandLine = ([executablePath] + arguments).joined(separator: " ")
            try Self.writeSetupLogHeader(title: title, commandLine: commandLine, to: logURL)
        } catch {
            showOnboardingStep(
                "Hmm, couldn't start setup — I wasn't able to make the log folder.",
                animation: "GetAttention",
                choices: [
                    .init(title: "Retry") { retry() },
                    .init(title: "Back") { [weak self] in self?.showBrainChoiceStep() },
                ]
            )
            return
        }

        let process = Process()
        let pipe = Pipe()
        let outputHandle: FileHandle
        do {
            outputHandle = try FileHandle(forWritingTo: logURL)
            try outputHandle.seekToEnd()
        } catch {
            showOnboardingStep(
                "Hmm, couldn't start setup — I wasn't able to write the log.",
                animation: "GetAttention",
                choices: [
                    .init(title: "Retry") { retry() },
                    .init(title: "Back") { [weak self] in self?.showBrainChoiceStep() },
                ]
            )
            return
        }

        if executablePath.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executablePath] + arguments
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        setupProcess = process
        setupOutputPipe = pipe
        setupOutputHandle = outputHandle
        openedSetupURLs.removeAll()

        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputHandle.write(data)
            guard
                let text = String(data: data, encoding: .utf8),
                let url = Self.firstSetupURL(in: text)
            else { return }
            Task { @MainActor [weak self, weak process] in
                self?.openSetupURLIfNeeded(url, process: process)
            }
        }
        process.terminationHandler = { [weak self, weak process] finishedProcess in
            pipe.fileHandleForReading.readabilityHandler = nil
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if !remaining.isEmpty {
                outputHandle.write(remaining)
            }
            try? outputHandle.close()
            Task { @MainActor [weak self, weak process] in
                guard let process else { return }
                self?.finishSetupProcess(
                    process,
                    logURL: logURL,
                    successMessage: successMessage,
                    retry: retry,
                    resume: resume,
                    status: finishedProcess.terminationStatus
                )
            }
        }

        showOnboardingStep(
            startMessage,
            animation: "GetTechy",
            choices: [
                .init(title: "Cancel") { [weak self] in
                    self?.cancelSetupProcess()
                    self?.showBrainChoiceStep()
                },
            ]
        )

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            setupProcess = nil
            setupOutputPipe = nil
            setupOutputHandle = nil
            try? outputHandle.close()
            showSetupFailure(logURL: logURL, retry: retry)
        }
    }

    private func finishSetupProcess(
        _ process: Process,
        logURL: URL,
        successMessage: String,
        retry: @escaping () -> Void,
        resume: @escaping () -> Void,
        status: Int32
    ) {
        guard setupProcess === process else {
            return
        }
        setupProcess = nil
        setupOutputPipe = nil
        setupOutputHandle = nil
        openedSetupURLs.removeAll()

        if status == 0 {
            showOnboardingStep(
                successMessage,
                animation: "Save",
                choices: [
                    .init(title: "Refresh") { resume() },
                    .init(title: "Back") { [weak self] in self?.showBrainChoiceStep() },
                ]
            )
        } else {
            showSetupFailure(logURL: logURL, retry: retry)
        }
    }

    private func showSetupFailure(logURL: URL, retry: @escaping () -> Void) {
        showOnboardingStep(
            "Welp, setup hit a snag. I saved the log if you wanna peek.",
            animation: "GetAttention",
            choices: [
                .init(title: "Retry") { retry() },
                .init(title: "Open Log") { NSWorkspace.shared.open(logURL) },
                .init(title: "Back") { [weak self] in self?.showBrainChoiceStep() },
            ]
        )
    }

    private func cancelSetupProcess() {
        setupOutputPipe?.fileHandleForReading.readabilityHandler = nil
        setupProcess?.terminationHandler = nil
        if let setupProcess, setupProcess.isRunning {
            setupProcess.terminate()
        }
        try? setupOutputHandle?.close()
        setupProcess = nil
        setupOutputPipe = nil
        setupOutputHandle = nil
        openedSetupURLs.removeAll()
    }

    private func openSetupURLIfNeeded(_ url: URL, process: Process?) {
        guard let process, setupProcess === process else {
            return
        }
        let key = url.absoluteString
        guard openedSetupURLs.insert(key).inserted else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    nonisolated private static func firstSetupURL(in text: String) -> URL? {
        guard let range = text.range(of: #"https?://[^\s<>"']+"#, options: .regularExpression) else {
            return nil
        }
        let raw = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,);]"))
        return URL(string: raw)
    }

    private static func setupLogURL(title: String) throws -> URL {
        let directory = try setupLogDirectory()
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return directory.appendingPathComponent("\(slug)-\(Int(Date().timeIntervalSince1970)).log")
    }

    private static func writeSetupLogHeader(title: String, commandLine: String, to url: URL) throws {
        let header = """
        Clippy setup: \(title)
        Started: \(Date())
        Command: \(commandLine)

        """
        try header.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func setupLogDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base
            .appendingPathComponent("Clippy", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Setup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func codexInstallCommand() -> String {
        """
        set -eu
        version="\(ClippyRuntimeLocator.codexVersion)"
        arch="$(uname -m)"
        case "$arch" in
          arm64)
            triple="aarch64-apple-darwin"
            url="https://registry.npmjs.org/@openai/codex/-/codex-0.140.0-darwin-arm64.tgz"
            expected="KDyQHsxdc8FHZKziSBXs82ABgben/8lLPdhi2Nu+wj6qs2RAp4k/IvE8foafVnp3OeGqhtEFbhlZp0H4Dg/Slg=="
            ;;
          x86_64)
            triple="x86_64-apple-darwin"
            url="https://registry.npmjs.org/@openai/codex/-/codex-0.140.0-darwin-x64.tgz"
            expected="xA77AcKbP8BKxKqaJz8bqXtU1dUtanEKpWCMJ68LuYU054EC31BD7NftFe5/vpLUQR95fhRr7V9a91SLtCuLAg=="
            ;;
          *)
            echo "Unsupported macOS architecture: $arch"
            exit 1
            ;;
        esac
        base="$HOME/Library/Application Support/Clippy/Runtimes/Codex/$version"
        tmp="$(mktemp -d)"
        cleanup() { rm -rf "$tmp"; }
        trap cleanup EXIT

        mkdir -p "$(dirname "$base")"
        /usr/bin/curl -fsSL "$url" -o "$tmp/runtime.tgz"
        actual="$(/usr/bin/openssl dgst -sha512 -binary "$tmp/runtime.tgz" | /usr/bin/openssl base64 -A)"
        if [ "$actual" != "$expected" ]; then
          echo "Downloaded ChatGPT connector did not pass verification."
          exit 1
        fi

        mkdir -p "$tmp/extract"
        /usr/bin/tar -xzf "$tmp/runtime.tgz" -C "$tmp/extract"
        test -x "$tmp/extract/package/vendor/$triple/bin/codex"

        rm -rf "$base"
        mkdir -p "$base/bin"
        cp -R "$tmp/extract/package/vendor" "$base/vendor"
        cat > "$base/bin/codex" <<'CLIPPY_CODEX'
        #!/bin/sh
        set -eu
        SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        arch="$(uname -m)"
        case "$arch" in
          arm64) triple="aarch64-apple-darwin" ;;
          x86_64) triple="x86_64-apple-darwin" ;;
          *) echo "Unsupported macOS architecture: $arch" >&2; exit 1 ;;
        esac
        path_dir="$SCRIPT_DIR/../vendor/$triple/codex-path"
        if [ -d "$path_dir" ]; then
          export PATH="$path_dir:${PATH:-}"
        fi
        exec "$SCRIPT_DIR/../vendor/$triple/bin/codex" "$@"
        CLIPPY_CODEX
        chmod 755 "$base/bin/codex"
        "$base/bin/codex" --help >/dev/null
        echo "ChatGPT connector installed."
        """
    }

    private static func claudeInstallCommand() -> String {
        """
        set -eu
        version="\(ClippyRuntimeLocator.claudeVersion)"
        arch="$(uname -m)"
        case "$arch" in
          arm64)
            url="https://registry.npmjs.org/@anthropic-ai/claude-code-darwin-arm64/-/claude-code-darwin-arm64-2.1.181.tgz"
            expected="nQlFIQyEIWQd7Pj4xET7+Kndm2kwp+kn9z9lbsS5CstMlYHs9ln9zpc/XYOYnsCcvwlSsVarYXQBREi6x/93ZA=="
            ;;
          x86_64)
            url="https://registry.npmjs.org/@anthropic-ai/claude-code-darwin-x64/-/claude-code-darwin-x64-2.1.181.tgz"
            expected="3u47rDjARgQboJ8HloeSHJrDphw9HbUV5YPWIi0ODM75Deyrh67GuXF/OroyQHiC4WwoqifGOhJu/KVDLPh5lA=="
            ;;
          *)
            echo "Unsupported macOS architecture: $arch"
            exit 1
            ;;
        esac
        base="$HOME/Library/Application Support/Clippy/Runtimes/Claude/$version"
        tmp="$(mktemp -d)"
        cleanup() { rm -rf "$tmp"; }
        trap cleanup EXIT

        mkdir -p "$(dirname "$base")"
        /usr/bin/curl -fsSL "$url" -o "$tmp/runtime.tgz"
        actual="$(/usr/bin/openssl dgst -sha512 -binary "$tmp/runtime.tgz" | /usr/bin/openssl base64 -A)"
        if [ "$actual" != "$expected" ]; then
          echo "Downloaded Claude connector did not pass verification."
          exit 1
        fi

        mkdir -p "$tmp/extract"
        /usr/bin/tar -xzf "$tmp/runtime.tgz" -C "$tmp/extract"
        test -x "$tmp/extract/package/claude"

        rm -rf "$base"
        mkdir -p "$base/bin"
        cp "$tmp/extract/package/claude" "$base/bin/claude"
        chmod 755 "$base/bin/claude"
        "$base/bin/claude" --version >/dev/null
        echo "Claude connector installed."
        """
    }

    /// Show the focused permission helper: a Clippy tile + an "Open System Settings"
    /// button. The bubble is hidden while this panel is active so the user has one
    /// instruction surface, not two competing ones.
    private func showPermissionDialog(
        permission: OnboardingPermission,
        doneButtonTitle: String = "Done",
        onDone: (() -> Void)? = nil
    ) {
        permissionDrag?.hide()
        chatBubble?.hide()
        playOnboardingAnimation(permission.animationName)
        let controller = PermissionDragController(
            appURL: Bundle.main.bundleURL,
            permissionName: permission.name,
            settingsAnchor: permission.settingsAnchor,
            allowsDragging: permission != .microphone,
            doneButtonTitle: doneButtonTitle,
            onDone: onDone
        )
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
        activeTTS()?.speak("It looks like you changed my voice. [chuckle] How's this?")
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        selectModel(id: id)
    }

    private func selectModel(id: String) {
        guard let model = ClippyModel.by(id: id) else { return }
        applySelectedModel(model)
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
    /// `snapshot`, `ground:`, `groundshot:`, `move:`, `park:`, `state:`.
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
            log("debug-command: \(debugCommandSummary(command))")
            if command.hasPrefix("ask:") {
                sendMessage(String(command.dropFirst(4)))
            } else if command.hasPrefix("askfront:") {
                askFront(command: String(command.dropFirst("askfront:".count)))
            } else if command == "open" {
                showTextInputBubble()
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
            } else if command.hasPrefix("groundshot:") {
                let parsed = GroundingParser.parse(String(command.dropFirst("groundshot:".count)))
                if isClippyHidden == false {
                    lastDesktopContext = DesktopContextSnapshot.capture()
                    let screenshotScreen = lastDesktopContext?.targetScreen() ?? screenForClippy()
                    lastShots = captureTurnScreenshots(primaryScreen: screenshotScreen)
                    lastShot = primaryShot(in: lastShots, primaryScreen: screenshotScreen)
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

    private func debugCommandSummary(_ command: String) -> String {
        if command.hasPrefix("ask:") {
            return "ask:\(String(command.dropFirst(4)).prefix(120))"
        }
        if command.hasPrefix("askfront:") {
            return "askfront"
        }
        if command.hasPrefix("ground:") {
            return "ground"
        }
        if command.hasPrefix("groundshot:") {
            return "groundshot"
        }
        return command
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
