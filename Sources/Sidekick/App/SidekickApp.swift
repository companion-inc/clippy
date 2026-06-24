import AppKit
import SidekickCore
import Sparkle

@main
@MainActor
final class SidekickApp: NSObject, NSApplicationDelegate {
    private enum UserAnnotationMode {
        case quick
        case sticky
    }

    private enum VoiceCapturePurpose {
        case command
        case wakeCommand
        case enrollment
    }

    private enum VoiceFilterMode: String {
        case off
        case onlyOwner

        var menuDetail: String {
            switch self {
            case .off: "Off"
            case .onlyOwner: "Only me"
            }
        }
    }

    private static let bodyScaleKey = "SidekickBodyScale"
    private static let selectedSidekickKey = "SidekickSelectedCharacterID"
    private static let setupCompletedKey = "SidekickSetupCompleted"
    private static let wakeWordEnabledKey = "SidekickWakeWordEnabled"
    private static let backgroundScreenSuggestionsEnabledKey = "SidekickBackgroundScreenSuggestionsEnabled"
    private static let voiceFilterModeKey = "SidekickVoiceFilterMode"
    private static let voiceFilterThreshold = 0.45
    private static let wakeCaptureInitialTimeout: TimeInterval = 6.0
    private static let wakeCaptureSpeechIdleTimeout: TimeInterval = 1.2
    private static let wakeCaptureMaxSpeechTimeout: TimeInterval = 12.0
    private static let voiceEnrollmentPhrases = [
        "I'm confused, what am I looking at here, and what should I do first?",
        "I don't know how to use this, can you walk me through the next couple of steps?",
        "Can you just do this task for me, and stop before anything risky or permanent?",
    ]
    private static let textInputShortcutHoldDelay: TimeInterval = 0.18
    private static let voiceShortcutHoldDelay: TimeInterval = 0.18
    private static let quickAnnotationHoldDelay: TimeInterval = 0.38
    private static let automaticTerminationReason = "Sidekick desktop assistant is running"
    private nonisolated static let shortcutModifierMask: NSEvent.ModifierFlags = [
        .control, .option, .command, .shift, .function
    ]

    private var sidekickCharacter: SidekickCharacter?
    private var pendingIdle: DispatchWorkItem?

    private var chatBubble: SidekickBubbleController?
    private var overlay: AnnotationOverlayWindow?
    private var annotationHold: ModifierHoldMonitor?
    private var userAnnotationController: UserAnnotationController?
    private var userAnnotation: UserScreenAnnotation?
    private var permissionDrag: PermissionDragController?
    private var permissionCharacterDragClear: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private var retroMenu = RetroMenuController()
    private var ptt: PushToTalkMonitor?
    private var textInputShortcut: KeyboardShortcutMonitor?
    private var clearMarksGlobalMonitor: Any?
    private var clearMarksLocalMonitor: Any?
    private var speech: SpeechCapture?
    private var deepgramSTT: DeepgramVoiceCapture?
    private var wakeWordMonitor: CoreMLWakeWordMonitor?
    private var tts: XAITTS?
    private var providerKeys: ProviderKeysController?
    private var setupProcess: Process?
    private var setupOutputPipe: Pipe?
    private var setupOutputHandle: FileHandle?
    private var speakerIdentityProcess: Process?
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
    private var activeVoiceCapturePurpose: VoiceCapturePurpose = .command
    private var voiceEnrollmentSamples: [VoiceCaptureAudio] = []
    private var voiceEnrollmentIndex = 0
    private var voicePressID = 0
    private var voicePartialText = ""
    private var wakeCaptureFinish: DispatchWorkItem?
    private var wakeCaptureHeardSpeech = false
    private var wakeCaptureVoiceActive = false
    private var hideBubbleWhenSpeechFinishes = false
    private var spokenBubbleShownAt: Date?
    private var spokenBubbleHide: DispatchWorkItem?
    private var codexComputerControlConversation: (any AgentBrain)?
    private var invocationRecommendationConversation: (any StructuredOutputAgentBrain)?
    private var invocationRecommendationBackend: SidekickModel.Backend?
    private var invocationRecommendationUnavailableBackends = Set<SidekickModel.Backend>()
    private var screenWakeConversation: (any StructuredOutputAgentBrain)?
    private var screenWakeBackend: SidekickModel.Backend?
    private var screenWakeUnavailableBackends = Set<SidekickModel.Backend>()
    private var backgroundScreenSuggestionTimer: Timer?
    private var isBackgroundScreenWakeRunning = false
    private var backgroundScreenWakeFailureCount = 0
    private let suggestionFeedbackStore = SidekickSuggestionFeedbackStore()
    private var sttEnabled = SidekickApp.defaultVoiceSetting(
        defaultsKey: "SidekickSTTEnabled",
        disableEnvironmentKey: "SIDEKICK_DISABLE_STT",
        legacyDisableEnvironmentKey: "CLIPPY_DISABLE_STT"
    )
    private var wakeWordEnabled = SidekickApp.defaultWakeWordSetting()
    private var backgroundScreenSuggestionsEnabled = UserDefaults.standard.bool(
        forKey: SidekickApp.backgroundScreenSuggestionsEnabledKey
    )
    private var ttsEnabled = SidekickApp.defaultVoiceSetting(
        defaultsKey: "SidekickTTSEnabled",
        disableEnvironmentKey: "SIDEKICK_DISABLE_TTS",
        legacyDisableEnvironmentKey: "CLIPPY_DISABLE_TTS"
    )
    private var voiceFilterMode: VoiceFilterMode = {
        let raw = UserDefaults.standard.string(forKey: SidekickApp.voiceFilterModeKey) ?? ""
        return VoiceFilterMode(rawValue: raw) ?? .off
    }()
    private var voiceFilterProfile = SpeakerIdentityProfileStore.load()
    private var conversation: (any AgentBrain)?
    private var selectedModel: SidekickModel = {
        // Honor an explicit prior choice; otherwise detect which subscription
        // (Claude vs GPT) the user is signed into locally and default to that.
        if let id = UserDefaults.standard.string(forKey: "SidekickSelectedModelID"),
           let saved = SidekickModel.by(id: id) {
            return saved
        }
        return BrainDiscovery.defaultModel()
    }()
    private var selectedVoice: SidekickVoice = {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "SidekickVoiceID"),
           let saved = SidekickVoice.by(id: id) {
            return saved
        }
        defaults.set(SidekickVoice.default.id, forKey: "SidekickVoiceID")
        return .default
    }()
    private var bodyScale: SidekickBodyScale = {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SidekickApp.bodyScaleKey) != nil else {
            return .default
        }
        return SidekickBodyScale(defaults.double(forKey: SidekickApp.bodyScaleKey))
    }()
    private var selectedSidekickSpec: SidekickSpec = {
        let env = ProcessInfo.processInfo.environment
        let raw = env["SIDEKICK_MASCOT"]
            ?? env["SIDEKICK_CHARACTER"]
            ?? UserDefaults.standard.string(forKey: SidekickApp.selectedSidekickKey)
        return raw.flatMap(SidekickSpec.by(id:)) ?? .clippy
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
    private var bubbleAnchorTimer: Timer?
    private var lastBubbleAnchorFrame: CGRect?
    private var activeActivityState: AgentActivityState = .idle
    private var activeTurnUsedUserAnnotation = false
    private var turnGeneration = 0
    private var isUserAnnotating = false
    private var isAnnotationHoldActive = false
    private var userAnnotationMode: UserAnnotationMode?
    private var annotationBeginWork: DispatchWorkItem?
    private var isSidekickHidden = false
    private var guidedTarget: GuidedTarget?
    private var guidedTargetClickMonitor: Any?
    private var guidedTargetHoverMonitor: Any?
    private var guidedTargetExpiry: DispatchWorkItem?
    private var guidedHoverRest: DispatchWorkItem?
    private var guidedCompletedSteps: [String] = []
    private var nextGuidedTargetRound = 0
    private let guidedTargetMaxRounds = 4
    private var explicitQuitRequested = false

    private struct ActiveUserRequest: Sendable {
        let text: String
        let inputMode: AssistantInputMode
        let attemptedModel: SidekickModel
    }

    private struct VisualGroundingContext: Sendable {
        let originalUserText: String
        let screenshotPath: String?
        let screenshotPixelWidth: Int
        let screenshotPixelHeight: Int
        let screenshots: [SidekickAgentInstructions.ScreenshotPromptContext]
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
        let delegate = SidekickApp()
        ProcessInfo.processInfo.disableAutomaticTermination(Self.automaticTerminationReason)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        // run() only returns via NSApp.stop (terminate exits the process from
        // inside). Reaching here means something stopped the run loop.
        delegate.log("NSApplication.run returned unexpectedly; exiting")
    }

    func applicationWillTerminate(_ notification: Notification) {
        disarmGuidedTarget(reason: "terminate")
        currentBrainTask?.cancel()
        currentBrainTask = nil
        conversation = nil
        codexComputerControlConversation = nil
        screenWakeConversation = nil
        cancelSetupProcess()
        textInputShortcut?.stop()
        stopClearMarksShortcut()
        stopBackgroundScreenSuggestions()
        annotationHold?.stop()
        userAnnotationController?.cancel()
        stopBubbleAnchorTracking()
        stopWakeWordMonitor()
        ptt?.stop()
        ProcessInfo.processInfo.enableAutomaticTermination(Self.automaticTerminationReason)
        log("applicationWillTerminate")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        explicitQuitRequested ? .terminateNow : .terminateCancel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        RetroFont.registerBundledFonts()
        startSidekick(Self.makeSidekickCharacter(spec: selectedSidekickSpec, bodyScale: bodyScale))
        overlay = AnnotationOverlayWindow()
        setUpBrain()
        setUpVoice()
        setUpShortcuts()
        startCommandChannel()
        configureBackgroundScreenSuggestions()
        showInitialSetupIfNeeded()
    }

    // MARK: - Sidekick setup

    private static func makeSidekickCharacter(spec: SidekickSpec, bodyScale: SidekickBodyScale) -> SidekickCharacter {
        do {
            return try SidekickCharacter(packRoot: characterResourceRoot(for: spec), spec: spec, bodyScale: bodyScale)
        } catch {
            fatalError("Sidekick resources failed to load for \(spec.displayName): \(error)")
        }
    }

    private func startSidekick(_ sidekickCharacter: SidekickCharacter, showGreeting: Bool = true) {
        let bubble = SidekickBubbleController(spec: sidekickCharacter.spec)

        self.sidekickCharacter = sidekickCharacter
        self.chatBubble = bubble

        bubble.setAnchor(sidekickCharacter.frame)
        bubble.setAnchorWindow(sidekickCharacter.windowController.window)
        bubble.configure { [weak self] text in
            self?.handleSubmittedText(text)
        }
        sidekickCharacter.windowController.onFrameChanged = { [weak self] frame in
            self?.syncBubbleAnchorToSidekick(frame: frame)
        }
        startBubbleAnchorTracking()
        sidekickCharacter.windowController.rightClickHandler = { [weak self] event, view in
            let point = view.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            self?.showRetroMenu(topLeft: point)
        }
        sidekickCharacter.windowController.onCharacterClick = { [weak self] in
            self?.handleCharacterClick()
        }
        sidekickCharacter.windowController.onCharacterDoubleClick = { [weak self] in
            self?.handleCharacterDoubleClick()
        }
        sidekickCharacter.windowController.onKeyDown = { [weak self] event in
            self?.handleClippyFocusedTyping(event) ?? false
        }
        setUpMenuBarItem()
        sidekickCharacter.show()
        sidekickCharacter.play(sidekickCharacter.spec.greetingAnimationName) { [weak self] _, _ in
            self?.scheduleNextIdle()
        }
        if showGreeting {
            bubble.showMessageForReading(sidekickCharacter.spec.greetingText)
        }
        scheduleDebugSnapshots()
    }

    private func setUpShortcuts() {
        let shortcut = KeyboardShortcutMonitor(
            keyCode: 49,
            modifiers: [.control],
            activationDelay: Self.textInputShortcutHoldDelay
        ) { [weak self] in
            self?.showTextInputFromShortcut()
        }
        textInputShortcut = shortcut
        shortcut.start()

        let annotation = ModifierHoldMonitor(modifiers: [.control], activationDelay: Self.quickAnnotationHoldDelay)
        annotation.onBegin = { [weak self] in self?.beginQuickUserAnnotationMode() }
        annotation.onEnd = { [weak self] in self?.finishQuickUserAnnotationMode() }
        annotation.onDoubleTap = { [weak self] in self?.toggleStickyUserAnnotationMode() }
        annotationHold = annotation
        annotation.start()
        startClearMarksShortcut()
    }

    private func handleCharacterClick() {
        if clearScreenMarks(reason: "sidekickCharacter-click", includeUserAnnotation: false) {
            return
        }
        toggleChat()
    }

    private func handleCharacterDoubleClick() {
        guard !isOnboardingActive else { return }
        cancelUserAnnotationMode()
        if isSidekickHidden {
            showSidekick()
        }
        syncBubbleAnchorToSidekick()
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

    private func recommendInvocationOptions(
        for context: DesktopContextSnapshot,
        proactiveAutoHide: Bool = false,
        accessibilityTree providedAccessibilityTree: DesktopAccessibilityTreeSnapshot? = nil,
        feedbackKey: SidekickSuggestionFeedbackKey? = nil
    ) {
        guard let chatBubble else { return }
        let recommendationLogPrefix = proactiveAutoHide
            ? "background-screen recommendations"
            : "double-click recommendations"
        guard let brain = invocationRecommendationBrain() else {
            log("\(recommendationLogPrefix) unavailable: brain missing")
            showInvocationFallback()
            return
        }
        let accessibilityTree = providedAccessibilityTree
            ?? DesktopAccessibilityTreeSnapshot.capture(desktopContext: context)
        guard accessibilityTree.nodes.isEmpty == false else {
            let issue = accessibilityTree.issue.map { " issue=\($0)" } ?? ""
            log("\(recommendationLogPrefix) ax-tree unavailable\(issue)")
            if proactiveAutoHide {
                return
            }
            if AccessibilityPermission.isTrusted == false {
                _ = AccessibilityPermission.requestIfNeeded(prompt: true)
                showPermissionDialog(permission: .accessibility)
            } else {
                showInvocationFallback()
            }
            return
        }
        log("\(recommendationLogPrefix) ax-tree: nodes=\(accessibilityTree.nodes.count)")
        if proactiveAutoHide == false {
            showComponentOutlines(
                for: accessibilityTree,
                context: context,
                reason: "double-click"
            )
        }
        lastShots = []
        lastShot = nil
        let prompt = SidekickAgentInstructions.brainMessage(
            text: SidekickInvocationSuggestions.recommendationPrompt(),
            screenshotPath: nil,
            screenshotPixelWidth: 0,
            screenshotPixelHeight: 0,
            inputMode: .text,
            speaking: false,
            desktopContext: context,
            accessibilityTree: accessibilityTree
        )

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
        syncBubbleAnchorToSidekick()
        chatBubble.showThinking("Reading the app")
        playActivityState(.thinking)
        scheduleTurnProgressUpdates(wantsScreen: false, attachedScreenshot: false)

        currentBrainTask = Task { [weak self] in
            let finalTurn = await brain.sendStructured(
                prompt,
                localImagePaths: [],
                outputSchema: SidekickInvocationSuggestions.recommendationSchema
            )
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self, self.turnGeneration == turnID else { return }
                self.cancelTurnProgressUpdates()
                self.currentBrainTask = nil
                self.isTurnRunning = false
                guard finalTurn.isError == false else {
                    let message = finalTurn.text.prefix(160)
                    self.log("\(recommendationLogPrefix) failed: \(message)")
                    self.handleInvocationRecommendationFailure(
                        finalTurn.text,
                        attemptedBackend: self.invocationRecommendationBackend
                    )
                    if self.invocationRecommendationBrain() != nil {
                        self.log("\(recommendationLogPrefix) retrying alternate hidden brain")
                        self.recommendInvocationOptions(
                            for: context,
                            proactiveAutoHide: proactiveAutoHide,
                            accessibilityTree: accessibilityTree,
                            feedbackKey: feedbackKey
                        )
                    } else {
                        self.showInvocationFallback()
                    }
                    return
                }
                guard let recommendation = SidekickInvocationSuggestions.parseRecommendation(from: finalTurn.text) else {
                    self.log("\(recommendationLogPrefix) empty: \(finalTurn.text.prefix(160))")
                    self.showInvocationFallback()
                    return
                }
                self.log("\(recommendationLogPrefix): \(recommendation.suggestions.map(\.title).joined(separator: ", "))")
                self.showInvocationOptions(
                    recommendation,
                    proactiveAutoHide: proactiveAutoHide,
                    feedbackKey: feedbackKey
                )
            }
        }
    }

    private func showInvocationOptions(
        _ recommendation: SidekickInvocationRecommendation,
        proactiveAutoHide: Bool = false,
        feedbackKey: SidekickSuggestionFeedbackKey? = nil
    ) {
        guard let chatBubble else { return }
        if let feedbackKey {
            let summary = suggestionFeedbackStore.recordImpression(for: feedbackKey)
            log("background-screen feedback impression key=\(feedbackKey.storageKey) shown=\(summary.impressions) ignored=\(summary.ignores) clicked=\(summary.engagements)")
        }
        let choices = recommendation.suggestions.map { suggestion in
            SidekickBubbleController.Choice(title: suggestion.title) { [weak self] in
                if let feedbackKey {
                    self?.recordProactiveSuggestionEngagement(feedbackKey)
                }
                self?.runInvocationSuggestion(suggestion)
            }
        } + [
            SidekickBubbleController.Choice(title: SidekickInvocationSuggestions.manualInputTitle) { [weak self] in
                if let feedbackKey {
                    self?.recordProactiveSuggestionEngagement(feedbackKey)
                }
                self?.showTextInputBubble()
            },
        ]
        let autoHide = proactiveAutoHide ? SidekickBubbleController.proactiveChoiceAutoHideDelay : nil
        _ = playOnce("GetAttention")
        chatBubble.showChoicesTyping(
            recommendation.message,
            choices: choices,
            autoHide: autoHide,
            onAutoHide: feedbackKey.map { key in
                { [weak self] in
                    let summary = self?.suggestionFeedbackStore.recordIgnore(for: key)
                    let remaining = summary?.suppressUntil.map { Int(ceil($0.timeIntervalSince(Date()))) } ?? 0
                    self?.log("background-screen feedback ignored key=\(key.storageKey) consecutive=\(summary?.consecutiveIgnores ?? 0) cooldown=\(remaining)s")
                }
            }
        )
    }

    private func recordProactiveSuggestionEngagement(_ feedbackKey: SidekickSuggestionFeedbackKey) {
        let summary = suggestionFeedbackStore.recordEngagement(for: feedbackKey)
        log("background-screen feedback clicked key=\(feedbackKey.storageKey) clicked=\(summary.engagements)")
    }

    private func showInvocationFallback() {
        _ = playOnce("GetAttention")
        showTextInputBubble()
    }

    private func showFocusedAppComponentOutlines(reason: String) {
        let context = DesktopContextSnapshot.capture()
        let accessibilityTree = DesktopAccessibilityTreeSnapshot.capture(desktopContext: context)
        guard accessibilityTree.nodes.isEmpty == false else {
            let issue = accessibilityTree.issue.map { " issue=\($0)" } ?? ""
            log("component-outlines skipped reason=\(reason)\(issue)")
            return
        }
        showComponentOutlines(for: accessibilityTree, context: context, reason: reason)
    }

    private func showComponentOutlines(
        for accessibilityTree: DesktopAccessibilityTreeSnapshot,
        context: DesktopContextSnapshot,
        reason: String
    ) {
        let frames = accessibilityTree.componentOutlineFrames(screen: context.screen, limit: 12)
        let marks = frames.map { AnnotationMark.rectangle(frame: $0) }
        guard marks.isEmpty == false else {
            log("component-outlines empty reason=\(reason)")
            return
        }
        let scene: DrawingScene
        if let anchor = DrawingWindowAnchor(desktopContext: context) {
            scene = DrawingScene(marks: marks, anchor: .window(anchor))
        } else {
            scene = DrawingScene(marks: marks)
        }
        let screen = context.targetScreen() ?? screenForSidekick()
        overlay?.show(scene, on: screen)
        log("component-outlines shown reason=\(reason) count=\(marks.count) source=ax")
    }

    private func switchSidekick(to rawID: String, announce: Bool = true) {
        guard let spec = SidekickSpec.by(id: rawID) else {
            log("sidekick switch ignored: unknown id=\(rawID)")
            return
        }
        guard spec.id != selectedSidekickSpec.id else {
            return
        }
        let previousSidekick = sidekickCharacter
        let previousFrame = sidekickCharacter?.frame
        let wasHidden = isSidekickHidden
        pendingIdle?.cancel()
        chatBubble?.hide()

        selectedSidekickSpec = spec
        UserDefaults.standard.set(spec.id, forKey: Self.selectedSidekickKey)
        let next = Self.makeSidekickCharacter(spec: spec, bodyScale: bodyScale)
        if let previousFrame {
            next.move(to: previousFrame.origin, animated: false)
        }
        isSidekickHidden = false
        startSidekick(next, showGreeting: false)
        previousSidekick?.windowController.hide()
        setUpBrain()
        if wasHidden {
            hideSidekick()
        } else if announce {
            syncBubbleAnchorToSidekick()
            chatBubble?.showReplyForReading("Switched to \(spec.displayName).")
            _ = playOnce(spec.openInputAnimationName)
        }
        updateMenuBarItem()
        log("sidekick selected: \(spec.id)")
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
                self?.syncBubbleAnchorToSidekick()
                self?.chatBubble?.showThinking("Still working")
            },
            .init(title: "Retry this") { [weak self] in
                self?.interruptSpeechAndResponse()
                self?.sendMessage(request.text, inputMode: request.inputMode)
            },
        ])
    }

    private func runInvocationSuggestion(_ suggestion: SidekickInvocationSuggestion) {
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
        guard let sidekickCharacter, !isTurnRunning, isSidekickHidden == false else {
            return
        }
        let name = sidekickCharacter.idleAnimationNames.randomElement() ?? "RestPose"
        sidekickCharacter.play(name) { [weak self, weak sidekickCharacter] _, endState in
            switch endState {
            case .waiting:
                sidekickCharacter?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    // MARK: - Brain

    private func applySelectedModel(_ model: SidekickModel) {
        selectedModel = model
        UserDefaults.standard.set(model.id, forKey: "SidekickSelectedModelID")
        setUpBrain()
    }

    private func setUpBrain() {
        codexComputerControlConversation = nil
        invocationRecommendationConversation = nil
        invocationRecommendationBackend = nil
        invocationRecommendationUnavailableBackends.removeAll()
        screenWakeConversation = nil
        screenWakeBackend = nil
        screenWakeUnavailableBackends.removeAll()
        backgroundScreenWakeFailureCount = 0
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch selectedModel.backend {
        case .claude:
            if let cli = LocalCLIConversation.locateBinary() {
                conversation = LocalCLIConversation(
                    binaryPath: cli,
                    workingDirectory: home,
                    systemPrompt: SidekickAgentInstructions.systemPrompt(for: selectedSidekickSpec),
                    model: selectedModel.id
                )
                log("brain: claude \(selectedModel.id)")
                prewarmBrain()
            } else {
                conversation = nil
                log("brain disabled: claude CLI not found")
            }
        case .codex:
            if let cli = CodexConversation.locateBinary() {
                conversation = CodexConversation(
                    binaryPath: cli,
                    model: selectedModel.id,
                    workingDirectory: home,
                    systemPrompt: SidekickAgentInstructions.systemPrompt(for: selectedSidekickSpec)
                )
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
            model: SidekickModel.gpt55.id,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        codexComputerControlConversation = brain
        log("brain: codex \(SidekickModel.gpt55.id) computer-control")
        Task {
            await brain.prepare()
        }
        return brain
    }

    private func invocationRecommendationBrain() -> (any StructuredOutputAgentBrain)? {
        if let invocationRecommendationConversation {
            return invocationRecommendationConversation
        }
        for backend in hiddenBrainBackendPreference(role: .invocationRecommendations) {
            guard invocationRecommendationUnavailableBackends.contains(backend) == false else {
                continue
            }
            let recommendationModel = SidekickModel.recommendationModel(for: backend)
            guard let brain = makeHiddenStructuredBrain(
                backend: backend,
                model: recommendationModel,
                role: "invocation-recommendations"
            ) else {
                continue
            }
            invocationRecommendationConversation = brain
            invocationRecommendationBackend = backend
            return brain
        }
        return nil
    }

    private func screenWakeBrain() -> (any StructuredOutputAgentBrain)? {
        if let screenWakeConversation {
            return screenWakeConversation
        }
        for backend in hiddenBrainBackendPreference(role: .backgroundScreenWake) {
            guard screenWakeUnavailableBackends.contains(backend) == false else {
                continue
            }
            let wakeModel = SidekickModel.notificationWakeModel(for: backend)
            guard let brain = makeHiddenStructuredBrain(
                backend: backend,
                model: wakeModel,
                role: "background-screen-wake"
            ) else {
                continue
            }
            screenWakeConversation = brain
            screenWakeBackend = backend
            return brain
        }
        return nil
    }

    private func hiddenBrainBackendPreference(role: SidekickHiddenBrainRole) -> [SidekickModel.Backend] {
        SidekickHiddenBrainRouting.backendPreference(
            selectedModel: selectedModel,
            role: role
        )
    }

    private func makeHiddenStructuredBrain(
        backend: SidekickModel.Backend,
        model: SidekickModel,
        role: String
    ) -> (any StructuredOutputAgentBrain)? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch backend {
        case .codex:
            guard let cli = CodexConversation.locateBinary(), BrainDiscovery.codexSignedIn() else {
                return nil
            }
            let brain = CodexConversation(
                binaryPath: cli,
                model: model.id,
                workingDirectory: home,
                systemPrompt: nil,
                computerUseRuntime: nil,
                annotationRuntime: nil,
                recordReplayRuntime: nil
            )
            log("brain: codex \(model.id) \(role)")
            Task { await brain.prepare() }
            return brain
        case .claude:
            guard let cli = LocalCLIConversation.locateBinary(), BrainDiscovery.claudeSignedIn() else {
                return nil
            }
            let brain = LocalCLIConversation(
                binaryPath: cli,
                allowedTools: [],
                workingDirectory: home,
                systemPrompt: nil,
                model: model.id
            )
            log("brain: claude \(model.id) \(role)")
            return brain
        }
    }

    private func configureBackgroundScreenSuggestions() {
        stopBackgroundScreenSuggestions()
        guard backgroundScreenSuggestionsEnabled else { return }
        if AccessibilityPermission.isTrusted == false {
            _ = AccessibilityPermission.requestIfNeeded(prompt: true)
        }
        let timer = Timer.scheduledTimer(
            withTimeInterval: SidekickBackgroundScreenSuggestions.defaultIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.runBackgroundScreenSuggestionCheck()
            }
        }
        backgroundScreenSuggestionTimer = timer
    }

    private func stopBackgroundScreenSuggestions() {
        backgroundScreenSuggestionTimer?.invalidate()
        backgroundScreenSuggestionTimer = nil
        isBackgroundScreenWakeRunning = false
    }

    private func runBackgroundScreenSuggestionCheck() {
        guard isBackgroundScreenWakeRunning == false,
              SidekickBackgroundScreenSuggestions.shouldRun(state: backgroundScreenSuggestionState())
        else {
            return
        }
        guard AccessibilityPermission.isTrusted else {
            log("background-screen-suggestions: skipped accessibility-missing")
            return
        }

        let desktopContext = DesktopContextSnapshot.capture()
        let accessibilityTree = DesktopAccessibilityTreeSnapshot.capture(desktopContext: desktopContext)
        guard accessibilityTree.nodes.isEmpty == false else {
            let issue = accessibilityTree.issue.map { " issue=\($0)" } ?? ""
            log("background-screen-suggestions: skipped ax-tree-empty\(issue)")
            return
        }
        let feedbackKey = SidekickSuggestionFeedback.contextKey(
            desktopContext: desktopContext,
            accessibilityTree: accessibilityTree
        )
        let now = Date()
        let feedbackSummary = suggestionFeedbackStore.summary(for: feedbackKey, now: now)
        let proactiveDecision = SidekickProactiveIntentRanker.rank(
            desktopContext: desktopContext,
            accessibilityTree: accessibilityTree,
            feedback: feedbackSummary,
            now: now
        )
        log("background-screen-suggestions ranker: \(proactiveDecision.logSummary)")
        if feedbackSummary.shouldSuppress(now: now), proactiveDecision.overridesFeedbackCooldown == false {
            let remaining = feedbackSummary.suppressUntil.map { Int(ceil($0.timeIntervalSince(now))) } ?? 0
            log("background-screen-suggestions: skipped feedback-cooldown key=\(feedbackKey.storageKey) remaining=\(remaining)s")
            return
        }
        switch proactiveDecision.action {
        case .doNothing, .watchForChange:
            log("background-screen-suggestions: skipped local-ranker \(proactiveDecision.logSummary)")
            return
        case .showOptions:
            log("background-screen-suggestions: local wake \(proactiveDecision.logSummary)")
            lastDesktopContext = desktopContext
            recommendInvocationOptions(
                for: desktopContext,
                proactiveAutoHide: true,
                accessibilityTree: accessibilityTree,
                feedbackKey: feedbackKey
            )
            return
        case .evaluateWithWakeModel:
            break
        }
        guard let brain = screenWakeBrain() else {
            log("background-screen-suggestions: skipped brain-missing")
            return
        }
        log("background-screen-suggestions ax-tree: nodes=\(accessibilityTree.nodes.count)")
        let prompt = SidekickAgentInstructions.brainMessage(
            text: SidekickBackgroundScreenSuggestions.wakePrompt(
                feedback: feedbackSummary,
                localDecision: proactiveDecision,
                now: now
            ),
            screenshotPath: nil,
            screenshotPixelWidth: 0,
            screenshotPixelHeight: 0,
            inputMode: .text,
            speaking: false,
            desktopContext: desktopContext,
            accessibilityTree: accessibilityTree
        )
        isBackgroundScreenWakeRunning = true

        Task { [weak self] in
            let finalTurn = await brain.sendStructured(
                prompt,
                localImagePaths: [],
                outputSchema: SidekickBackgroundScreenSuggestions.wakeSchema
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isBackgroundScreenWakeRunning = false
                guard finalTurn.isError == false else {
                    self.log("background-screen-suggestions wake failed: \(finalTurn.text.prefix(160))")
                    self.handleBackgroundScreenWakeFailure(
                        finalTurn.text,
                        attemptedBackend: self.screenWakeBackend
                    )
                    return
                }
                guard SidekickBackgroundScreenSuggestions.shouldRun(state: self.backgroundScreenSuggestionState()) else {
                    self.log("background-screen-suggestions: paused after wake")
                    return
                }
                guard let decision = SidekickBackgroundScreenSuggestions.parseWakeDecision(from: finalTurn.text) else {
                    self.log("background-screen-suggestions wake empty: \(finalTurn.text.prefix(160))")
                    self.handleBackgroundScreenWakeFailure(
                        finalTurn.text,
                        attemptedBackend: self.screenWakeBackend
                    )
                    return
                }
                self.backgroundScreenWakeFailureCount = 0
                guard decision.shouldShowOptions else {
                    self.log("background-screen-suggestions: no wake\(decision.reason.map { " reason=\($0)" } ?? "")")
                    return
                }
                self.log("background-screen-suggestions: wake\(decision.reason.map { " reason=\($0)" } ?? "")")
                self.lastDesktopContext = desktopContext
                self.recommendInvocationOptions(
                    for: desktopContext,
                    proactiveAutoHide: true,
                    accessibilityTree: accessibilityTree,
                    feedbackKey: feedbackKey
                )
            }
        }
    }

    private func backgroundScreenSuggestionState() -> SidekickBackgroundScreenSuggestionState {
        SidekickBackgroundScreenSuggestionState(
            enabled: backgroundScreenSuggestionsEnabled,
            isTurnRunning: isTurnRunning,
            isVoiceCaptureActive: isVoiceCaptureActive,
            isPushToTalkHeld: isPushToTalkHeld,
            isTTSSpeaking: tts?.isSpeaking ?? false,
            isPresentingChoices: chatBubble?.isPresentingChoices ?? false,
            isInputMode: chatBubble?.isInputMode ?? false,
            isUserAnnotating: isUserAnnotating,
            isAnnotationHoldActive: isAnnotationHoldActive,
            isOnboardingActive: isOnboardingActive,
            isWorkflowRecording: currentChronicleRecording()?.state == .recording,
            hasGuidedTarget: guidedTarget != nil,
            isSidekickHidden: isSidekickHidden
        )
    }

    private func handleInvocationRecommendationFailure(_ text: String, attemptedBackend: SidekickModel.Backend?) {
        if let attemptedBackend {
            invocationRecommendationUnavailableBackends.insert(attemptedBackend)
        }
        invocationRecommendationConversation = nil
        invocationRecommendationBackend = nil
        if let issue = SidekickUserFacingError.providerIssue(for: text) {
            log("double-click recommendations hidden brain disabled after \(attemptedBackend?.rawValue ?? "unknown") \(issue)")
        }
    }

    private func handleBackgroundScreenWakeFailure(_ text: String, attemptedBackend: SidekickModel.Backend?) {
        backgroundScreenWakeFailureCount += 1
        if let attemptedBackend {
            screenWakeUnavailableBackends.insert(attemptedBackend)
        }
        screenWakeConversation = nil
        screenWakeBackend = nil
        if let issue = SidekickUserFacingError.providerIssue(for: text) {
            log("background-screen-suggestions: hidden brain disabled after \(attemptedBackend?.rawValue ?? "unknown") \(issue)")
        }

        if screenWakeUnavailableBackends.count >= hiddenBrainBackendPreference(role: .backgroundScreenWake).count
            || SidekickBackgroundScreenSuggestions.shouldDisable(afterConsecutiveWakeFailures: backgroundScreenWakeFailureCount) {
            backgroundScreenSuggestionsEnabled = false
            UserDefaults.standard.set(false, forKey: Self.backgroundScreenSuggestionsEnabledKey)
            stopBackgroundScreenSuggestions()
            log("background-screen-suggestions: disabled after repeated wake failures")
        }
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
            stopWakeWordMonitor()
            log("voice: STT disabled; TTS \(ttsEnabled ? "enabled" : "disabled")")
            return
        }
        configureVoiceProviders()

        let monitor = PushToTalkMonitor(modifiers: [.control, .option], activationDelay: Self.voiceShortcutHoldDelay)
        monitor.onBegin = { [weak self] in self?.beginVoiceTurn() }
        monitor.onEnd = { [weak self] in self?.endVoiceTurn() }
        self.ptt = monitor
        monitor.start()
        configureWakeWordMonitor()
    }

    private func configureVoiceProviders() {
        deepgramSTT?.cancel()
        tts?.stop()
        stopWakeWordMonitor()
        cancelSpokenBubbleHide()
        cancelWakeCaptureFinish()
        isVoiceCaptureActive = false
        usingDeepgram = false
        wakeCaptureHeardSpeech = false
        wakeCaptureVoiceActive = false
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        deepgramSTT = DeepgramVoiceCapture()
        tts = nil
        speech = deepgramSTT == nil ? SpeechCapture() : nil
        installVoiceProviderCallbacks()
        log("voice: deepgram STT=\(deepgramSTT != nil) xAI TTS key=\(SidekickSecrets.xaiAPIKey != nil)")
    }

    private static func defaultVoiceSetting(
        defaultsKey: String,
        disableEnvironmentKey: String,
        legacyDisableEnvironmentKey: String
    ) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard !environmentFlag(environment["SIDEKICK_DISABLE_VOICE"] ?? environment["CLIPPY_DISABLE_VOICE"]),
              !environmentFlag(environment[disableEnvironmentKey] ?? environment[legacyDisableEnvironmentKey]) else {
            return false
        }
        return UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    private static func defaultWakeWordSetting() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environmentFlag(environment["SIDEKICK_ENABLE_WAKE_WORD"] ?? environment["CLIPPY_ENABLE_WAKE_WORD"]) {
            return true
        }
        guard !environmentFlag(environment["SIDEKICK_DISABLE_VOICE"] ?? environment["CLIPPY_DISABLE_VOICE"]),
              !environmentFlag(environment["SIDEKICK_DISABLE_WAKE_WORD"] ?? environment["CLIPPY_DISABLE_WAKE_WORD"]) else {
            return false
        }
        return UserDefaults.standard.object(forKey: wakeWordEnabledKey) as? Bool ?? false
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
        deepgramSTT?.onVoiceActivityChanged = { [weak self] isSpeechActive in
            self?.handleVoiceActivity(isSpeechActive)
        }
        speech?.onPartialTranscript = { [weak self] text in
            self?.showLiveTranscript(text)
        }
        speech?.onVoiceActivityChanged = { [weak self] isSpeechActive in
            self?.handleVoiceActivity(isSpeechActive)
        }
        if let tts {
            installTTSCallbacks(tts)
        }
    }

    private func configureWakeWordMonitor() {
        stopWakeWordMonitor()
        guard wakeWordEnabled, sttEnabled else {
            return
        }
        guard MicrophonePermission.isGranted else {
            log("wake-word: waiting for microphone permission")
            return
        }
        if CoreMLWakeWordMonitor.needsSpeechVerificationAuthorization {
            log("wake-word: requesting Speech Recognition for local phrase verifier")
            Task { [weak self] in
                let granted = await CoreMLWakeWordMonitor.requestSpeechVerificationAuthorization()
                await MainActor.run {
                    guard let self else { return }
                    self.log("wake-word: speech verifier permission \(granted ? "granted" : "denied")")
                    if granted {
                        self.configureWakeWordMonitor()
                    }
                }
            }
            return
        }
        guard CoreMLWakeWordMonitor.isSpeechVerificationAuthorized else {
            log("wake-word: Speech Recognition permission required for local phrase verifier")
            return
        }
        guard let modelURL = WakeWordModelLocator.defaultModelURL() else {
            log("wake-word: model missing; set \(WakeWordModelLocator.environmentKey) or install HeyClippy.mlmodel")
            return
        }
        let configuration = CoreMLWakeWordMonitor.Configuration(modelURL: modelURL)
        let monitor = CoreMLWakeWordMonitor(configuration: configuration)
        monitor.onWake = { [weak self] detection in
            self?.handleWakeWord(detection)
        }
        monitor.onError = { [weak self] message in
            self?.log("wake-word error: \(message)")
        }
        do {
            try monitor.start()
            wakeWordMonitor = monitor
            log("wake-word: listening label=hey_clippy model=\(modelURL.path)")
        } catch {
            log("wake-word start failed: \(error)")
        }
    }

    private func stopWakeWordMonitor() {
        wakeWordMonitor?.stop()
        wakeWordMonitor = nil
    }

    private func restartWakeWordMonitorIfNeeded() {
        guard wakeWordEnabled, sttEnabled, wakeWordMonitor == nil else { return }
        configureWakeWordMonitor()
    }

    private func handleWakeWord(_ detection: WakeWordDetection) {
        guard wakeWordEnabled, sttEnabled else { return }
        guard !isVoiceCaptureActive, !isVoiceEnrollmentActive, !isOnboardingActive else { return }
        if isSidekickHidden {
            showSidekick()
        }
        syncBubbleAnchorToSidekick()
        chatBubble?.showStatus("Listening...")
        log("wake-word: accepted label=\(detection.label) confidence=\(detection.confidence)")
        stopWakeWordMonitor()
        startVoiceCapture(purpose: .wakeCommand)
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
              isSidekickHidden == false else {
            return
        }
        voicePartialText = trimmed
        if let frame = sidekickCharacter?.frame { chatBubble?.setAnchor(frame) }
        chatBubble?.showStatus(trimmed)
        if activeVoiceCapturePurpose == .wakeCommand {
            wakeCaptureHeardSpeech = true
            if wakeCaptureVoiceActive == false {
                scheduleWakeCaptureFinish(after: Self.wakeCaptureSpeechIdleTimeout, reason: "transcript-idle")
            }
        }
    }

    private func handleVoiceActivity(_ isSpeechActive: Bool) {
        guard isVoiceCaptureActive,
              activeVoiceCapturePurpose == .wakeCommand else {
            return
        }
        wakeCaptureVoiceActive = isSpeechActive
        if isSpeechActive {
            wakeCaptureHeardSpeech = true
            scheduleWakeCaptureFinish(after: Self.wakeCaptureMaxSpeechTimeout, reason: "max-speech")
        } else if wakeCaptureHeardSpeech {
            scheduleWakeCaptureFinish(after: Self.wakeCaptureSpeechIdleTimeout, reason: "vad-silence")
        }
    }

    private func handleTTSActivity(_ speaking: Bool) {
        if speaking {
            pendingIdle?.cancel()
            cancelSpokenBubbleHide()
            return
        }
        if hideBubbleWhenSpeechFinishes {
            if isSidekickHidden == false, !isTurnRunning {
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
        let delay = SidekickBubbleController.spokenAutoHideDelay(visibleFor: visibleFor)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.spokenBubbleHide = nil
            guard self.hideBubbleWhenSpeechFinishes,
                  self.isSidekickHidden == false,
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
        guard isPushToTalkHeld == false, isVoiceCaptureActive == false else { return }
        guard !isAnnotationHoldActive, !isUserAnnotating else { return }
        isPushToTalkHeld = true
        voicePressID += 1
        let pressID = voicePressID
        let purpose: VoiceCapturePurpose = isVoiceEnrollmentActive ? .enrollment : .command
        if isSidekickHidden {
            showSidekick()
            log("wake shortcut: sidekickCharacter shown")
            return
        }
        guard sttEnabled, conversation != nil || purpose == .enrollment else {
            return
        }
        if needsVoicePermissionForCurrentProvider() {
            requestVoicePermissionForPushToTalk(pressID: pressID)
            return
        }
        startVoiceCapture(purpose: purpose)
    }

    private func needsVoicePermissionForCurrentProvider() -> Bool {
        if deepgramSTT != nil {
            return !MicrophonePermission.isGranted
        }
        return !MicrophonePermission.isGranted || SpeechCapture.speechAuthorizationStatus != .authorized
    }

    private func requestVoicePermissionForPushToTalk(pressID: Int) {
        let needsSpeechRecognition = (deepgramSTT == nil)
        if let frame = sidekickCharacter?.frame { chatBubble?.setAnchor(frame) }
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
        startVoiceCapture(purpose: isVoiceEnrollmentActive ? .enrollment : .command)
    }

    private func startVoiceCapture(purpose: VoiceCapturePurpose = .command) {
        guard isVoiceCaptureActive == false else { return }
        // Barge-in: starting to talk interrupts whatever
        // Sidekick is currently saying or still generating, instead of being blocked.
        stopWakeWordMonitor()
        cancelWakeCaptureFinish()
        interruptSpeechAndResponse()
        activeVoiceCapturePurpose = purpose
        usingDeepgram = false
        isVoiceCaptureActive = false
        voicePartialText = ""
        wakeCaptureHeardSpeech = false
        wakeCaptureVoiceActive = false
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
            guard let speech else {
                restartWakeWordMonitorIfNeeded()
                return
            }
            do {
                try speech.start()
                captureStarted = true
            } catch {
                log("apple stt start failed: \(error)")
                restartWakeWordMonitorIfNeeded()
                return
            }
        }
        guard captureStarted else {
            restartWakeWordMonitorIfNeeded()
            return
        }
        isVoiceCaptureActive = true
        pendingIdle?.cancel()
        if isSidekickHidden == false {
            if let frame = sidekickCharacter?.frame { chatBubble?.setAnchor(frame) }
            chatBubble?.showStatus(purpose == .enrollment ? "Recording voice sample..." : "Listening...")
        }
        if purpose == .wakeCommand {
            scheduleWakeCaptureFinish(after: Self.wakeCaptureInitialTimeout, reason: "initial-timeout")
        }
        log("ptt: listening (deepgram=\(usingDeepgram))")
    }

    private func endVoiceTurn() {
        isPushToTalkHeld = false
        finishActiveVoiceCapture()
    }

    private func finishActiveVoiceCapture() {
        cancelWakeCaptureFinish()
        guard isVoiceCaptureActive else { return }
        isVoiceCaptureActive = false
        let purpose = activeVoiceCapturePurpose
        if usingDeepgram, let deepgram = deepgramSTT {
            deepgram.finishResult { [weak self] result in
                self?.handleVoiceCaptureResult(result, purpose: purpose)
            }
            return
        }
        // Apple fallback: 400ms tail so trailing words aren't clipped, then finalize.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let speech = self.speech else { return }
            self.handleVoiceCaptureResult(speech.stopResult(), purpose: purpose)
        }
    }

    private func scheduleWakeCaptureFinish(after delay: TimeInterval, reason: String) {
        cancelWakeCaptureFinish()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.activeVoiceCapturePurpose == .wakeCommand,
                  self.isVoiceCaptureActive else {
                return
            }
            self.log("wake-word: finishing capture reason=\(reason)")
            self.finishActiveVoiceCapture()
        }
        wakeCaptureFinish = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelWakeCaptureFinish() {
        wakeCaptureFinish?.cancel()
        wakeCaptureFinish = nil
    }

    private func handleVoiceCaptureResult(_ result: VoiceCaptureResult, purpose: VoiceCapturePurpose) {
        activeVoiceCapturePurpose = .command
        wakeCaptureHeardSpeech = false
        wakeCaptureVoiceActive = false
        switch purpose {
        case .command, .wakeCommand:
            handleCommandVoiceCapture(result)
            restartWakeWordMonitorIfNeeded()
        case .enrollment:
            handleVoiceEnrollmentSample(result.audio)
            restartWakeWordMonitorIfNeeded()
        }
    }

    private func handleCommandVoiceCapture(_ result: VoiceCaptureResult) {
        let transcript = result.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcript.isEmpty == false else {
            chatBubble?.hide()
            return
        }
        guard voiceFilterMode == .onlyOwner else {
            handleTranscript(transcript)
            return
        }
        guard let profile = voiceFilterProfile else {
            setVoiceFilterMode(.off, announce: false)
            chatBubble?.showChoicesTyping("Voice filter needs a voice profile first.", choices: [
                .init(title: "Learn my voice") { [weak self] in self?.startVoiceEnrollment() },
                .init(title: "Keep it off") { [weak self] in self?.chatBubble?.hide() },
            ])
            return
        }
        guard result.audio.isEmpty == false else {
            chatBubble?.showReplyForReading("(No voice audio to check.)")
            return
        }
        chatBubble?.showThinking("Checking voice")
        Task { [weak self] in
            do {
                guard let self else { return }
                guard await self.ensureSpeakerIdentityService() else {
                    await MainActor.run {
                        self.log("voice filter identify skipped: sidecar unavailable")
                        self.chatBubble?.showReplyForReading("(Voice filter isn't ready.)")
                    }
                    return
                }
                let match = try await self.makeSpeakerIdentityClient().identify(
                    sample: result.audio,
                    profiles: [profile],
                    threshold: Self.voiceFilterThreshold
                )
                await MainActor.run {
                    self.finishVoiceFilterCheck(match: match, profile: profile, transcript: transcript)
                }
            } catch {
                await MainActor.run {
                    self?.log("voice filter identify failed: \(error)")
                    self?.chatBubble?.showReplyForReading("(Voice filter isn't ready.)")
                }
            }
        }
    }

    private func finishVoiceFilterCheck(
        match: SpeakerIdentityResult,
        profile: SpeakerIdentityProfile,
        transcript: String
    ) {
        let scoreText = match.score.map { String($0) } ?? "nil"
        if match.userId == profile.userId {
            log("voice filter: accepted score=\(scoreText)")
            handleTranscript(transcript)
        } else {
            log("voice filter: ignored score=\(scoreText)")
            chatBubble?.showReplyForReading("(Ignored: different voice.)")
        }
    }

    private var isVoiceEnrollmentActive: Bool {
        voiceEnrollmentIndex > 0
    }

    private var voiceFilterMenuDetail: String {
        if voiceFilterMode == .onlyOwner, voiceFilterProfile == nil {
            return "Set up"
        }
        return voiceFilterMode.menuDetail
    }

    private func startVoiceEnrollment() {
        if !sttEnabled {
            sttEnabled = true
            UserDefaults.standard.set(sttEnabled, forKey: "SidekickSTTEnabled")
        }
        if ptt == nil {
            setUpVoice()
        }
        syncBubbleAnchorToSidekick()
        chatBubble?.showThinking("Checking voice ID")
        Task { [weak self] in
            guard let self else { return }
            let ready = await self.ensureSpeakerIdentityService()
            await MainActor.run {
                if ready {
                    self.beginVoiceEnrollmentSamples()
                } else {
                    self.showVoiceIdentityUnavailable()
                }
            }
        }
    }

    private func beginVoiceEnrollmentSamples() {
        voiceEnrollmentSamples = []
        voiceEnrollmentIndex = 1
        showVoiceEnrollmentPrompt()
    }

    private func showVoiceEnrollmentPrompt() {
        let index = max(1, min(voiceEnrollmentIndex, Self.voiceEnrollmentPhrases.count))
        let phrase = Self.voiceEnrollmentPhrases[index - 1]
        showOnboardingStep(
            "Question \(index)/\(Self.voiceEnrollmentPhrases.count). Hold Control+Option and answer: \"\(phrase)\"",
            animation: "Hearing_1",
            choices: [
                .init(title: "Cancel") { [weak self] in self?.cancelVoiceEnrollment() },
            ]
        )
    }

    private func handleVoiceEnrollmentSample(_ audio: VoiceCaptureAudio) {
        guard isVoiceEnrollmentActive else { return }
        guard audio.durationSeconds >= 1.0 else {
            showOnboardingStep(
                "That answer was too short. Hold Control+Option and answer again.",
                animation: "Hearing_1",
                choices: [
                    .init(title: "Try again") { [weak self] in self?.showVoiceEnrollmentPrompt() },
                    .init(title: "Cancel") { [weak self] in self?.cancelVoiceEnrollment() },
                ]
            )
            return
        }
        voiceEnrollmentSamples.append(audio)
        if voiceEnrollmentSamples.count < Self.voiceEnrollmentPhrases.count {
            voiceEnrollmentIndex = voiceEnrollmentSamples.count + 1
            showVoiceEnrollmentPrompt()
            return
        }
        finishVoiceEnrollment()
    }

    private func finishVoiceEnrollment() {
        let samples = voiceEnrollmentSamples
        voiceEnrollmentIndex = 0
        voiceEnrollmentSamples = []
        chatBubble?.showThinking("Learning your voice")
        let client = makeSpeakerIdentityClient()
        Task { [weak self] in
            do {
                let profile = try await client.enroll(samples: samples)
                try SpeakerIdentityProfileStore.save(profile)
                await MainActor.run {
                    self?.voiceFilterProfile = profile
                    self?.setVoiceFilterMode(.onlyOwner, announce: false)
                    self?.log("voice filter: profile enrolled samples=\(samples.count) dims=\(profile.embedding.count)")
                    self?.chatBubble?.showReplyForReading("Voice filter is on. I'll only answer that voice.")
                }
            } catch {
                await MainActor.run {
                    self?.log("voice filter enroll failed: \(error)")
                    self?.chatBubble?.showChoicesTyping("I couldn't save that voice profile.", choices: [
                        .init(title: "Try again") { [weak self] in self?.startVoiceEnrollment() },
                        .init(title: "Cancel") { [weak self] in self?.cancelVoiceEnrollment() },
                    ])
                }
            }
        }
    }

    private func cancelVoiceEnrollment() {
        voiceEnrollmentIndex = 0
        voiceEnrollmentSamples = []
        activeVoiceCapturePurpose = .command
        chatBubble?.showReplyForReading("Voice setup cancelled.")
    }

    private func showVoiceIdentityUnavailable() {
        let url = speakerIdentityBaseURL().absoluteString
        chatBubble?.showChoicesTyping("I couldn't start Voice ID at \(url). Check /tmp/sidekickCharacter-speaker-id.log, then try again.", choices: [
            .init(title: "Try again") { [weak self] in self?.startVoiceEnrollment() },
            .init(title: "Cancel") { [weak self] in self?.cancelVoiceEnrollment() },
        ])
    }

    private func setVoiceFilterMode(_ mode: VoiceFilterMode, announce: Bool = true) {
        guard mode != .onlyOwner || voiceFilterProfile != nil else {
            startVoiceEnrollment()
            return
        }
        voiceFilterMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.voiceFilterModeKey)
        guard announce else { return }
        switch mode {
        case .off:
            chatBubble?.showReplyForReading("Voice filter is off.")
        case .onlyOwner:
            chatBubble?.showReplyForReading("Voice filter is on. Only your voice reaches me.")
        }
    }

    private func clearVoiceFilterProfile() {
        do {
            try SpeakerIdentityProfileStore.delete()
        } catch {
            log("voice filter profile delete failed: \(error)")
        }
        voiceFilterProfile = nil
        setVoiceFilterMode(.off, announce: false)
        chatBubble?.showReplyForReading("Voice profile cleared.")
    }

    private func makeSpeakerIdentityClient() -> SpeakerIdentityClient {
        SpeakerIdentityClient(baseURL: speakerIdentityBaseURL())
    }

    private func ensureSpeakerIdentityService() async -> Bool {
        let client = makeSpeakerIdentityClient()
        if (try? await client.health()) != nil {
            return true
        }
        do {
            try startSpeakerIdentityProcessIfNeeded()
        } catch {
            log("voice filter sidecar start failed: \(error)")
            return false
        }
        return await waitForSpeakerIdentityHealth(client: client)
    }

    private func waitForSpeakerIdentityHealth(client: SpeakerIdentityClient) async -> Bool {
        for _ in 0..<24 {
            if (try? await client.health()) != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private func startSpeakerIdentityProcessIfNeeded() throws {
        if speakerIdentityProcess?.isRunning == true {
            return
        }
        speakerIdentityProcess = nil
        guard let workingDirectory = speakerIdentityWorkingDirectory() else {
            throw NSError(
                domain: "SidekickSpeakerIdentity",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing local iris-speaker-id runtime"]
            )
        }
        let python = workingDirectory
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
        let process = Process()
        process.executableURL = python
        process.arguments = [
            "-m",
            "uvicorn",
            "iris_speaker_id.server:app",
            "--host",
            "127.0.0.1",
            "--port",
            "4749",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_DISABLE_XET"] = "1"
        environment["PYTHONPATH"] = "src"
        process.environment = environment
        process.currentDirectoryURL = workingDirectory

        let logURL = URL(fileURLWithPath: "/tmp/sidekickCharacter-speaker-id.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
        }
        try process.run()
        speakerIdentityProcess = process
        log("voice filter sidecar started pid=\(process.processIdentifier) dir=\(workingDirectory.path)")
    }

    private func speakerIdentityWorkingDirectory() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let configured = existingSpeakerIdentityDirectory(environment["SIDEKICK_SPEAKER_ID_DIR"] ?? environment["CLIPPY_SPEAKER_ID_DIR"]) {
            return configured
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home
                .appendingPathComponent("Library/Application Support/Sidekick/VoiceSidecar", isDirectory: true)
                .appendingPathComponent("iris-speaker-id", isDirectory: true),
            home
                .appendingPathComponent("Library/Application Support/Iris/Runtime", isDirectory: true)
                .appendingPathComponent("apps", isDirectory: true)
                .appendingPathComponent("iris-speaker-id", isDirectory: true),
            home
                .appendingPathComponent("Library/Application Support/Iris/Runtime.backup.20260531122010", isDirectory: true)
                .appendingPathComponent("apps", isDirectory: true)
                .appendingPathComponent("iris-speaker-id", isDirectory: true),
        ]
        return candidates.first(where: isSpeakerIdentityDirectory)
    }

    private func existingSpeakerIdentityDirectory(_ path: String?) -> URL? {
        guard let path, path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        return isSpeakerIdentityDirectory(url) ? url : nil
    }

    private func isSpeakerIdentityDirectory(_ url: URL) -> Bool {
        let python = url
            .appendingPathComponent(".venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python")
        let server = url
            .appendingPathComponent("src", isDirectory: true)
            .appendingPathComponent("iris_speaker_id", isDirectory: true)
            .appendingPathComponent("server.py")
        return FileManager.default.isExecutableFile(atPath: python.path)
            && FileManager.default.fileExists(atPath: server.path)
    }

    private func speakerIdentityBaseURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        let raw = environment["SIDEKICK_SPEAKER_ID_URL"]
            ?? environment["CLIPPY_SPEAKER_ID_URL"]
            ?? environment["IRIS_SPEAKER_ID_URL"]
            ?? "http://127.0.0.1:4749"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:4749")!
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
        if chatBubble.isPresentingChoices {
            return chatBubble.receiveChoiceKey(event) ?? true
        }
        let inputAlreadyOpen = chatBubble.isInputMode
        guard SidekickBubbleController.acceptsExternalInputKey(
            keyCode: event.keyCode,
            characters: event.characters,
            modifierFlags: event.modifierFlags,
            inputAlreadyOpen: inputAlreadyOpen
        ) else {
            return false
        }
        if isSidekickHidden {
            showSidekick()
        }
        syncBubbleAnchorToSidekick()
        pendingIdle?.cancel()
        let accepted = chatBubble.receiveExternalInputKey(event)
        if accepted, !inputAlreadyOpen {
            log("focused-type: captured keyCode=\(event.keyCode)")
            sidekickCharacter?.play(sidekickCharacter?.spec.openInputAnimationName ?? "GetAttention") { [weak sidekickCharacter] _, state in
                if state == .waiting {
                    sidekickCharacter?.exitCurrentAnimation()
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
        startQuickUserAnnotationModeIfStillHolding()
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
        let annotationAnchor = currentUserAnnotationAnchor()
        if isSidekickHidden {
            showSidekick()
        }
        userAnnotationMode = .quick
        isUserAnnotating = true
        pendingIdle?.cancel()
        overlay?.clear()
        let controller = userAnnotationController ?? UserAnnotationController()
        userAnnotationController = controller
        controller.begin(existing: userAnnotation, anchor: annotationAnchor)
        syncBubbleAnchorToSidekick()
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
        let annotationAnchor = currentUserAnnotationAnchor()
        if isSidekickHidden {
            showSidekick()
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
            anchor: annotationAnchor,
            showsToolbar: true,
            toolbarActions: UserAnnotationToolbarActions(
                done: { [weak self] in self?.finishCurrentUserAnnotationMode(logReason: "sticky") },
                clear: { [weak self] in self?.clearStickyUserAnnotationMode() },
                cancel: { [weak self] in self?.cancelUserAnnotationMode() }
            )
        )
        syncBubbleAnchorToSidekick()
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
            syncBubbleAnchorToSidekick()
            chatBubble?.showReplyForReading("No marks yet.")
            log("user-annotation: \(logReason)-empty")
            return
        }
        userAnnotation = annotation
        showUserAnnotationOverlay()
        syncBubbleAnchorToSidekick()
        chatBubble?.showReplyForReading("Marked. Ask me what you want to know.")
        _ = playOnce("Explain")
        log("user-annotation: \(logReason)-finish strokes=\(annotation.strokes.count) screen=\(annotation.screenIndex + 1)")
    }

    private func clearStickyUserAnnotationMode() {
        guard userAnnotationMode == .sticky, isUserAnnotating else { return }
        userAnnotation = nil
        userAnnotationController?.clear()
        overlay?.clear()
        syncBubbleAnchorToSidekick()
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
        syncBubbleAnchorToSidekick()
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

    private func currentUserAnnotationAnchor() -> DrawingAnchor {
        let desktopContext = DesktopContextSnapshot.capture()
        guard let anchor = DrawingWindowAnchor(desktopContext: desktopContext) else {
            return .screen
        }
        return .window(anchor)
    }

    private func screen(forUserAnnotation annotation: UserScreenAnnotation) -> NSScreen? {
        if case let .window(anchor) = annotation.anchor {
            let frame = anchor.currentFrame() ?? anchor.initialFrame
            if let screen = ScreenPerception.screen(containing: frame) {
                return screen
            }
        }
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
        if isSidekickHidden {
            showSidekick()
        }
        syncBubbleAnchorToSidekick()
        chatBubble?.showReplyForReading("Double-tap Control for annotation mode, or hold Control for a quick mark.")
        _ = playOnce("GetAttention")
    }

    private func showTextInputBubble(prefilledText: String = "") {
        guard let sidekickCharacter, let chatBubble else {
            return
        }
        if isSidekickHidden {
            showSidekick()
        }
        chatBubble.setAnchor(sidekickCharacter.frame)
        if chatBubble.isInputMode {
            if prefilledText.isEmpty == false {
                chatBubble.openInput(prefilledText: prefilledText)
                return
            }
            chatBubble.focusInput()
            return
        }
        sidekickCharacter.play(sidekickCharacter.spec.openInputAnimationName) { [weak sidekickCharacter] _, state in
            if state == .waiting {
                sidekickCharacter?.exitCurrentAnimation()
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
        forcedModel: SidekickModel? = nil,
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
        let needsToolLane = SidekickAgentInstructions.shouldUseCodexToolLane(text: text, inputMode: inputMode)
        let needsComputerControl = SidekickAgentInstructions.shouldUseComputerControl(text: text, inputMode: inputMode)
        let needsVisualGrounding = SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: text, inputMode: inputMode)
        let toolLaneBrain = (!forceSelectedProvider && needsToolLane) ? computerControlBrain() : nil
        let activeBrain = toolLaneBrain ?? conversation
        let attemptedModel = forcedModel ?? (toolLaneBrain == nil ? selectedModel : .gpt55)
        guard let activeBrain else {
            log("brain unavailable for message: \(text.prefix(120))")
            if isSidekickHidden == false {
                syncBubbleAnchorToSidekick()
                chatBubble.showReplyForReading("(My local brain isn't installed.)")
            }
            return
        }
        let desktopContext = DesktopContextSnapshot.capture()
        lastDesktopContext = desktopContext
        log("desktop-context: \(desktopContext.logSummary)")
        let wantsScreen = SidekickAgentInstructions.shouldAttachScreenshot(
            text: text,
            inputMode: inputMode,
            desktopContext: desktopContext
        )
        if requestTurnPermissionIfNeeded(needsComputerControl: needsComputerControl, wantsScreen: wantsScreen) {
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
        let screenshotScreen = desktopContext.targetScreen() ?? screenForSidekick()
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
        if isSidekickHidden == false {
            syncBubbleAnchorToSidekick()
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
        let speaking = ttsEnabled && SidekickSecrets.xaiAPIKey != nil
        let brainMessage = SidekickAgentInstructions.brainMessage(
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

    private func requestTurnPermissionIfNeeded(needsComputerControl: Bool, wantsScreen: Bool) -> Bool {
        if needsComputerControl && AccessibilityPermission.isTrusted == false {
            log("turn permission request: accessibility")
            _ = AccessibilityPermission.requestIfNeeded(prompt: true)
            showPermissionDialog(permission: .accessibility)
            return true
        }

        if wantsScreen && ScreenPerception.hasPermission == false {
            log("turn permission request: screen-recording")
            _ = ScreenPerception.requestPermission()
            showPermissionDialog(permission: .screenRecording)
            return true
        }

        return false
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
        guard isTurnRunning, !turnHasStreamingText, isSidekickHidden == false else { return }
        syncBubbleAnchorToSidekick()
        chatBubble?.updateThinking(status)
    }

    private func cancelTurnProgressUpdates() {
        turnProgressItems.forEach { $0.cancel() }
        turnProgressItems.removeAll()
    }

    private func cancelTurnTimeout() {
        // Sidekick does not impose a local deadline on model turns. Provider errors
        // and user interruption still end the turn through the normal paths.
    }

    private func captureTurnScreenshot(screen targetScreen: NSScreen?) -> ScreenPerception.Screenshot? {
        let sidekickWindow = sidekickCharacter?.windowController.window
        let belowWindowNumber = sidekickWindow?.isVisible == true ? sidekickWindow?.windowNumber : nil

        overlay?.clear()
        let shot = ScreenPerception.captureToFile(screen: targetScreen, belowWindowNumber: belowWindowNumber)
        showUserAnnotationOverlay()
        return shot
    }

    private func captureTurnScreenshots(primaryScreen targetScreen: NSScreen?) -> [ScreenPerception.Screenshot] {
        let sidekickWindow = sidekickCharacter?.windowController.window
        let belowWindowNumber = sidekickWindow?.isVisible == true ? sidekickWindow?.windowNumber : nil

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
    ) -> [SidekickAgentInstructions.ScreenshotPromptContext] {
        screenshots.map { shot in
            SidekickAgentInstructions.ScreenshotPromptContext(
                path: shot.path,
                pixelWidth: Int(shot.pixelSize.width),
                pixelHeight: Int(shot.pixelSize.height),
                screenNumber: shot.screenIndex + 1,
                isPrimary: shot.screenIndex == primary?.screenIndex && shot.screenFrame == primary?.screenFrame
            )
        }
    }

    private func startBubbleAnchorTracking() {
        stopBubbleAnchorTracking()
        syncBubbleAnchorToSidekick()
        bubbleAnchorTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncBubbleAnchorToSidekick()
            }
        }
    }

    private func stopBubbleAnchorTracking() {
        bubbleAnchorTimer?.invalidate()
        bubbleAnchorTimer = nil
        lastBubbleAnchorFrame = nil
    }

    private func syncBubbleAnchorToSidekick(frame providedFrame: CGRect? = nil) {
        guard let frame = providedFrame ?? sidekickCharacter?.frame else {
            return
        }
        guard lastBubbleAnchorFrame?.equalTo(frame) != true else {
            return
        }
        lastBubbleAnchorFrame = frame
        chatBubble?.setAnchor(frame)
    }

    /// Speak the reply as it streams: enqueue each newly-completed sentence (tags
    /// stripped) so Sidekick talks before the whole reply lands. `final` flushes the
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
        let speakable = SidekickRichReply.parse(clean).text
        if let friendly = SidekickUserFacingError.replacement(for: clean, isError: false) {
            tts.enqueue(friendly)
        } else if !speakable.isEmpty {
            tts.enqueue(speakable)
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
        cancelWakeCaptureFinish()
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
        guard isSidekickHidden == false else { return }
        if let frame = sidekickCharacter?.frame { chatBubble?.setAnchor(frame) }
        let display = SidekickUserFacingError.replacement(for: text, isError: false)
            ?? VoiceSpeechTags.stripForStreaming(GroundingParser.stripForStreaming(text))
        if !display.isEmpty {
            turnHasStreamingText = true
            cancelTurnProgressUpdates()
            chatBubble?.showReply(display, allowsRichMedia: false)
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
        if isSidekickHidden {
            log("sidekickCharacter: \(turn.text.prefix(120))")
            return
        }
        if let frame = sidekickCharacter?.frame { chatBubble?.setAnchor(frame) }
        if offerProviderFallbackIfAvailable(turn.text) {
            log("sidekickCharacter: \(turn.text.prefix(120))")
            return
        }
        let friendlyFailure = SidekickUserFacingError.replacement(for: turn.text, isError: turn.isError)
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
        // Runtime failures get a Sidekick-shaped sentence; normal replies show only
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
        log("sidekickCharacter: \(turn.text.prefix(120))")

        if !turn.isError, !visualTags.isEmpty {
            presentGrounding(visualTags, instructionText: spoken)
            return
        }
        overlay?.clear()
        playActivityState(turn.isError ? .error : .attention)

        let animationName = turn.isError
            ? (sidekickCharacter?.spec.errorAnimationName ?? "Alert")
            : (sidekickCharacter?.spec.replyAnimationName ?? "Explain")
        sidekickCharacter?.play(animationName) { [weak self, weak sidekickCharacter] _, state in
            switch state {
            case .waiting:
                sidekickCharacter?.exitCurrentAnimation()
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
        let animationName = sidekickCharacter?.spec.replyAnimationName ?? "Explain"
        sidekickCharacter?.play(animationName) { [weak self, weak sidekickCharacter] _, state in
            switch state {
            case .waiting:
                sidekickCharacter?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    private func selectProviderAfterIssue(_ offer: BrainFallbackOffer, retrying request: ActiveUserRequest) {
        applySelectedModel(offer.toModel)
        log("model selected: \(offer.toModel.id) after \(offer.fromProviderName) provider fallback; retrying")
        if let frame = sidekickCharacter?.frame { chatBubble?.setAnchor(frame) }
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
        if let frame = sidekickCharacter?.frame { chatBubble?.setAnchor(frame) }
        sendMessage(
            request.text,
            inputMode: request.inputMode,
            initialThinkingStatus: "Trying \(offer.fromProviderName) again"
        )
    }

    private func discardProviderIssue(_ offer: BrainFallbackOffer) {
        activeUserRequest = nil
        overlay?.clear()
        syncBubbleAnchorToSidekick()
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
        syncBubbleAnchorToSidekick()
        chatBubble?.showThinking("Finding the spot")
        playActivityState(.thinking)
        let repairMessage = SidekickAgentInstructions.visualGroundingRepairMessage(
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

    /// Render parsed grounding directives: draw the marks, and move Sidekick beside the
    /// first anchored target so it points at it with the matching body gesture.
    private func presentGrounding(_ rawTags: [GroundingTag], instructionText: String? = nil) {
        guard isSidekickHidden == false else {
            return
        }
        let fallbackScreen = screenForSidekick() ?? NSScreen.main ?? NSScreen.screens.first
        let screen = screenForGrounding(rawTags) ?? screenForLastShot() ?? fallbackScreen
        guard let screen else { return }
        // The model emitted coordinates in the screenshot's pixel space; map them onto
        // the actual screen so the ring and Sidekick's body land in the right place.
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
            // Point at a target with Sidekick's body.
            moveSidekickToPoint(at: anchor, in: screen)
        } else if let animation = firstActAnimation(in: tags) {
            // Emote: Sidekick performs the animation it asked for, in place.
            pendingIdle?.cancel()
            if playOnce(animation) == false {
                log("unknown animation requested: \(animation)")
                scheduleNextIdle()
            }
        }
    }

    private func moveSidekickToPoint(at anchor: CGPoint, in screen: NSScreen) {
        guard let sidekickCharacter else { return }
        pendingIdle?.cancel()
        let size = sidekickCharacter.frame.size
        let origin = GroundingDirector.parkOrigin(beside: anchor, sidekickSize: size, in: screen.visibleFrame)
        let finalFrame = CGRect(origin: origin, size: size)
        sidekickCharacter.windowController.move(to: origin, animated: true) { [weak self, weak sidekickCharacter] in
            if let frame = sidekickCharacter?.frame {
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
        let screenshotScreen = desktopContext.targetScreen() ?? screenForSidekick()
        let shots = captureTurnScreenshots(primaryScreen: screenshotScreen)
        let shot = primaryShot(in: shots, primaryScreen: screenshotScreen)
        lastShots = shots
        lastShot = shot
        if shots.isEmpty == false {
            logScreenCaptures(shots, primary: shot)
        } else {
            log("screen-capture: unavailable")
        }

        if isSidekickHidden == false {
            syncBubbleAnchorToSidekick()
            chatBubble?.showThinking("Checking that step")
        }
        scheduleTurnProgressUpdates(wantsScreen: true, attachedScreenshot: shot != nil)
        playActivityState(.thinking)

        let message = SidekickAgentInstructions.guidedTargetFollowUpMessage(
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

    private func screenForSidekick() -> NSScreen? {
        guard let sidekickCharacter else { return NSScreen.main ?? NSScreen.screens.first }
        return ScreenPerception.screen(containing: sidekickCharacter.frame)
            ?? sidekickCharacter.windowController.window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Plays `name` once, holding-then-exiting branched animations and returning to
    /// idle when it ends. Returns false if `name` isn't in the character pack.
    @discardableResult
    private func playOnce(_ name: String) -> Bool {
        guard let sidekickCharacter else { return false }
        return sidekickCharacter.play(name) { [weak self, weak sidekickCharacter] _, state in
            switch state {
            case .waiting:
                sidekickCharacter?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    private func playActivityState(_ state: AgentActivityState) {
        activeActivityState = state
        pendingIdle?.cancel()
        guard isSidekickHidden == false else {
            return
        }
        guard state != .idle else {
            scheduleNextIdle()
            return
        }
        guard let binding = sidekickCharacter?.spec.animation(for: state) else {
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
        if isSidekickHidden {
            showSidekick()
        } else {
            hideSidekick()
        }
    }

    private func hideSidekick() {
        guard isSidekickHidden == false else { return }
        isSidekickHidden = true
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
        clearPermissionCharacterDrag()
        _ = speech?.stop()
        tts?.stop()
        sidekickCharacter?.windowController.hide()
        log("sidekickCharacter hidden")
    }

    private func showSidekick() {
        guard isSidekickHidden else { return }
        isSidekickHidden = false
        updateMenuBarItem()
        sidekickCharacter?.show()
        if let frame = sidekickCharacter?.frame {
            chatBubble?.setAnchor(frame)
        }
        log("sidekickCharacter shown")
        if isTurnRunning {
            playActivityState(activeActivityState)
        } else {
            scheduleNextIdle()
        }
    }

    private func playTransient(_ name: String) {
        sidekickCharacter?.play(name) { [weak self, weak sidekickCharacter] _, state in
            switch state {
            case .waiting:
                sidekickCharacter?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    /// Plays an animation and keeps replaying it while that activity state remains visible.
    private func playLooping(_ name: String, while activityState: AgentActivityState) {
        sidekickCharacter?.play(name) { [weak self] _, endState in
            guard let self else {
                return
            }
            switch endState {
            case .waiting:
                self.sidekickCharacter?.exitCurrentAnimation()
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
        button.image = Self.makeEyeStatusImage(hidden: isSidekickHidden)
        button.imagePosition = .imageOnly
        button.toolTip = isSidekickHidden ? "Show Sidekick" : "Hide Sidekick"
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
            .action(sidekickCharacter?.spec.chatMenuTitle ?? SidekickSpec.current.chatMenuTitle) { [weak self] in
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
            isSidekickHidden ? "Show Sidekick" : "Hide Sidekick",
            detail: isSidekickHidden ? "Hold Ctrl+Option" : nil,
            icon: isSidekickHidden ? .eye : .eyeSlash
        ) { [weak self] in
            self?.toggleClippyVisibility()
        })

        items.append(.separator())
        items.append(.toggle("Mute Sounds", isOn: sidekickCharacter?.isMuted ?? false) { [weak self] in
            self?.toggleMute()
        })
        items.append(.toggle("Voice Input (hold Ctrl+Option)", isOn: sttEnabled) { [weak self] in
            self?.toggleSTT()
        })
        items.append(.toggle("Wake Word (Hey Clippy)", isOn: wakeWordEnabled) { [weak self] in
            self?.toggleWakeWord()
        })
        items.append(.toggle("Auto Desktop Suggestions", isOn: backgroundScreenSuggestionsEnabled) { [weak self] in
            self?.toggleBackgroundScreenSuggestions()
        })
        items.append(.toggle("Speak Replies", isOn: ttsEnabled) { [weak self] in
            self?.toggleTTS()
        })
        items.append(.action("Annotate Screen", detail: "Ctrl Ctrl") { [weak self] in
            self?.startStickyUserAnnotationMode()
        })
        if currentChronicleRecording()?.state == .recording {
            items.append(.action("Stop Recording and Make Skill") { [weak self] in
                self?.stopWorkflowRecordingAndMakeSkill()
            })
            items.append(.action("Cancel Recording") { [weak self] in
                self?.cancelWorkflowRecording()
            })
        } else {
            items.append(.action("Record Workflow...") { [weak self] in
                self?.startWorkflowRecording()
            })
        }

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
        items.append(.submenu("Sidekick Size", detail: bodyScale.percentTitle, items: bodySizeItems))

        let sidekickItems = SidekickSpec.all.map { spec in
            RetroMenuItem.choice(spec.displayName, isSelected: spec.id == selectedSidekickSpec.id) { [weak self] in
                self?.switchSidekick(to: spec.id)
            }
        }
        items.append(.separator())
        items.append(.submenu("Sidekick", detail: selectedSidekickSpec.displayName, items: sidekickItems))

        let modelItems = SidekickModel.all.map { model in
            RetroMenuItem.choice(model.displayName, isSelected: model.id == selectedModel.id) { [weak self] in
                self?.selectModel(id: model.id)
            }
        }
        items.append(.submenu("Model", detail: selectedModel.displayName, items: modelItems))

        let voiceItems = SidekickVoice.all.map { voice in
            RetroMenuItem.choice(voice.displayName, detail: voice.detail, isSelected: voice.id == selectedVoice.id) { [weak self] in
                self?.selectVoice(id: voice.id)
            }
        }
        items.append(.submenu("Voice", detail: selectedVoice.detail, items: voiceItems))

        let hasVoiceProfile = voiceFilterProfile != nil
        let voiceFilterItems: [RetroMenuItem] = [
            .choice("Off", isSelected: voiceFilterMode == .off) { [weak self] in
                self?.setVoiceFilterMode(.off)
            },
            .choice(
                "Only My Voice",
                detail: hasVoiceProfile ? nil : "Set up first",
                isSelected: voiceFilterMode == .onlyOwner
            ) { [weak self] in
                self?.setVoiceFilterMode(.onlyOwner)
            },
            .separator(),
            .action("Learn My Voice...") { [weak self] in
                self?.startVoiceEnrollment()
            },
            .action("Clear Voice Profile", detail: hasVoiceProfile ? nil : "No profile") { [weak self] in
                self?.clearVoiceFilterProfile()
            },
        ]
        items.append(.submenu("Voice Filter", detail: voiceFilterMenuDetail, items: voiceFilterItems))

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
        items.append(.action("Quit Sidekick") { [weak self] in
            self?.quitSidekick()
        })
        return items
    }

    private func currentChronicleRecording() -> ChronicleSessionMetadata? {
        guard let metadata = try? SidekickChronicleRecorder.shared.status(),
              metadata.state == .recording else {
            return nil
        }
        return metadata
    }

    private func startWorkflowRecording() {
        guard !isTurnRunning else {
            syncBubbleAnchorToSidekick()
            chatBubble?.showReplyForReading("Let me finish this first, then record the workflow.")
            return
        }
        if !AccessibilityPermission.isTrusted {
            _ = AccessibilityPermission.requestIfNeeded(prompt: true)
        }
        do {
            let metadata = try SidekickChronicleRecorder.shared.start()
            log("record-replay: started id=\(metadata.id) events=\(metadata.eventsPath)")
            syncBubbleAnchorToSidekick()
            playActivityState(.attention)
            let warning = metadata.warning == nil ? "" : " I may miss some clicks until Accessibility is allowed."
            chatBubble?.showReplyForReading("Recording. Do the workflow, then choose Stop Recording and Make Skill.\(warning)")
        } catch {
            log("record-replay start failed: \(error.localizedDescription)")
            syncBubbleAnchorToSidekick()
            chatBubble?.showReplyForReading("I couldn't start recording: \(error.localizedDescription)")
        }
    }

    private func stopWorkflowRecordingAndMakeSkill() {
        do {
            let metadata = try SidekickChronicleRecorder.shared.stop()
            log("record-replay: stopped id=\(metadata.id) events=\(metadata.eventsPath) frames=\(metadata.frameCount)")
            syncBubbleAnchorToSidekick()
            chatBubble?.showThinking("Creating the skill")
            let prompt = Self.recordingSkillPrompt(metadata: metadata)
            sendMessage(
                prompt,
                inputMode: .text,
                initialThinkingStatus: "Creating the skill",
                visibleUserLine: "Create a skill from that recording."
            )
        } catch {
            log("record-replay stop failed: \(error.localizedDescription)")
            syncBubbleAnchorToSidekick()
            chatBubble?.showReplyForReading("I couldn't stop the recording: \(error.localizedDescription)")
        }
    }

    private func cancelWorkflowRecording() {
        do {
            let metadata = try SidekickChronicleRecorder.shared.cancel()
            log("record-replay: cancelled id=\(metadata.id)")
            syncBubbleAnchorToSidekick()
            chatBubble?.showReplyForReading("Recording cancelled.")
        } catch {
            log("record-replay cancel failed: \(error.localizedDescription)")
            syncBubbleAnchorToSidekick()
            chatBubble?.showReplyForReading("I couldn't cancel the recording: \(error.localizedDescription)")
        }
    }

    private static func recordingSkillPrompt(metadata: ChronicleSessionMetadata) -> String {
        """
        Create a reusable skill from this Sidekick Chronicle recording.

        Read the recording metadata and event stream from disk:
        - session.json: \(metadata.metadataPath)
        - events.jsonl: \(metadata.eventsPath)
        - frames: \(metadata.framesDirectory)

        Treat events.jsonl as the primary evidence of the workflow. Infer the durable workflow goal, do not create a coordinate-only macro, omit sensitive captured values, and create or refine a real discoverable skill folder. Default to ~/.codex/skills unless the recording proves a project-local skill is the right scope. Validate the skill before saying it is done.
        """
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
        guard let sidekickCharacter else {
            return
        }
        let name = sidekickCharacter.gestureAnimationNames.randomElement() ?? sidekickCharacter.spec.fallbackGestureAnimationName
        sidekickCharacter.play(name) { [weak self, weak sidekickCharacter] _, endState in
            switch endState {
            case .waiting:
                sidekickCharacter?.exitCurrentAnimation()
            case .exited:
                self?.scheduleNextIdle()
            }
        }
    }

    @objc private func toggleMute() {
        sidekickCharacter?.isMuted.toggle()
    }

    @objc private func toggleSTT() {
        sttEnabled.toggle()
        UserDefaults.standard.set(sttEnabled, forKey: "SidekickSTTEnabled")
        if sttEnabled {
            if ptt == nil {
                setUpVoice()
            } else {
                configureWakeWordMonitor()
            }
        } else {
            let wasCapturing = isVoiceCaptureActive
            cancelWakeCaptureFinish()
            isVoiceCaptureActive = false
            usingDeepgram = false
            deepgramSTT?.cancel()
            if wasCapturing {
                _ = speech?.stop()
            }
            stopWakeWordMonitor()
            ptt?.stop()
            ptt = nil
        }
    }

    @objc private func toggleWakeWord() {
        wakeWordEnabled.toggle()
        UserDefaults.standard.set(wakeWordEnabled, forKey: Self.wakeWordEnabledKey)
        guard wakeWordEnabled else {
            stopWakeWordMonitor()
            chatBubble?.showReplyForReading("Wake word is off.")
            return
        }

        if !sttEnabled {
            sttEnabled = true
            UserDefaults.standard.set(true, forKey: "SidekickSTTEnabled")
            if ptt == nil {
                setUpVoice()
            }
        }

        guard WakeWordModelLocator.defaultModelURL() != nil else {
            stopWakeWordMonitor()
            chatBubble?.showReplyForReading("Train HeyClippy.mlmodel, then turn wake word on again.")
            return
        }

        guard MicrophonePermission.isGranted else {
            syncBubbleAnchorToSidekick()
            chatBubble?.showStatus("Allow microphone access for Hey Clippy.")
            Task { [weak self] in
                let granted = await SpeechCapture.requestMicrophone()
                await MainActor.run {
                    guard let self, self.wakeWordEnabled else { return }
                    if granted {
                        self.configureWakeWordMonitor()
                    } else {
                        self.chatBubble?.showReplyForReading("(Microphone access is off.)")
                    }
                }
            }
            return
        }

        configureWakeWordMonitor()
        if wakeWordMonitor != nil {
            chatBubble?.showReplyForReading("Wake word is on.")
        }
    }

    @objc private func toggleBackgroundScreenSuggestions() {
        backgroundScreenSuggestionsEnabled.toggle()
        UserDefaults.standard.set(
            backgroundScreenSuggestionsEnabled,
            forKey: Self.backgroundScreenSuggestionsEnabledKey
        )
        guard backgroundScreenSuggestionsEnabled else {
            stopBackgroundScreenSuggestions()
            chatBubble?.showReplyForReading("Auto desktop suggestions are off.")
            return
        }

        backgroundScreenWakeFailureCount = 0
        screenWakeUnavailableBackends.removeAll()
        screenWakeConversation = nil
        screenWakeBackend = nil

        guard AccessibilityPermission.isTrusted else {
            configureBackgroundScreenSuggestions()
            _ = AccessibilityPermission.requestIfNeeded(prompt: true)
            showPermissionDialog(permission: .accessibility)
            chatBubble?.showReplyForReading("Auto desktop suggestions are on after Accessibility is allowed.")
            return
        }

        configureBackgroundScreenSuggestions()
        chatBubble?.showReplyForReading("Auto desktop suggestions are on.")
    }

    @objc private func toggleTTS() {
        ttsEnabled.toggle()
        UserDefaults.standard.set(ttsEnabled, forKey: "SidekickTTSEnabled")
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

    private func setBodyScale(_ scale: SidekickBodyScale) {
        bodyScale = scale
        UserDefaults.standard.set(scale.value, forKey: Self.bodyScaleKey)
        if let sidekickCharacter {
            sidekickCharacter.resizeBody(to: scale, in: screenForSidekick()?.visibleFrame ?? NSScreen.main?.visibleFrame, animated: true)
        }
        log("body size: \(scale.percentTitle)")
        guard isSidekickHidden == false else { return }
        syncBubbleAnchorToSidekick()
        chatBubble?.showReplyForReading("Sidekick size \(scale.percentTitle).")
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
        Task { [weak self] in
            let granted = await SpeechCapture.requestMicrophone()
            await MainActor.run {
                if granted {
                    self?.restartWakeWordMonitorIfNeeded()
                }
            }
        }
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
                self?.restartWakeWordMonitorIfNeeded()
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
            } else if !SidekickSecrets.missingRequiredProviderNames.isEmpty {
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
        if isSidekickHidden {
            showSidekick()
        }
        cancelSpokenBubbleHide()
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        isOnboardingActive = true
        syncBubbleAnchorToSidekick()
        if force {
            clearOnboardingResumePoint()
            showWelcomeStep()
        } else {
            resumeBubbleOnboarding()
        }
    }

    private func saveOnboardingResumePoint(_ point: SidekickOnboardingResumePoint) {
        UserDefaults.standard.set(point.rawValue, forKey: SidekickOnboardingResumePoint.defaultsKey)
    }

    private func clearOnboardingResumePoint() {
        UserDefaults.standard.removeObject(forKey: SidekickOnboardingResumePoint.defaultsKey)
    }

    private func savedOnboardingResumePoint() -> SidekickOnboardingResumePoint {
        SidekickOnboardingResumePoint.savedPoint(
            from: UserDefaults.standard.string(forKey: SidekickOnboardingResumePoint.defaultsKey)
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
        case .screenHelp, .fileAccess, .demo, .controls:
            showOnboardingControlsStep(createdPageURL: nil)
        }
    }

    private func showWelcomeStep() {
        saveOnboardingResumePoint(.welcome)
        showOnboardingStep(
            "Hi, I'm \(selectedSidekickSpec.displayName). Let's get this set up — it's quick.",
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
        if SidekickSecrets.deepgramAPIKey != nil {
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
        if SidekickSecrets.xaiAPIKey != nil {
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
        UserDefaults.standard.set(true, forKey: "SidekickSTTEnabled")
        configureVoiceProviders()
        if ptt == nil {
            setUpVoice()
        } else {
            restartWakeWordMonitorIfNeeded()
        }
        guard !MicrophonePermission.isGranted else {
            showVoiceStep()
            return
        }
        syncBubbleAnchorToSidekick()
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
        UserDefaults.standard.set(false, forKey: "SidekickSTTEnabled")
        if isVoiceCaptureActive {
            _ = speech?.stop()
        }
        isVoiceCaptureActive = false
        usingDeepgram = false
        deepgramSTT?.cancel()
        stopWakeWordMonitor()
        cancelWakeCaptureFinish()
        ptt?.stop()
        ptt = nil
        showVoiceStep()
    }

    private func enableOnboardingSpeech() {
        ttsEnabled = true
        UserDefaults.standard.set(true, forKey: "SidekickTTSEnabled")
        configureVoiceProviders()
        restartWakeWordMonitorIfNeeded()
        showOnboardingControlsStep(createdPageURL: nil)
    }

    private func skipOnboardingSpeech() {
        ttsEnabled = false
        UserDefaults.standard.set(false, forKey: "SidekickTTSEnabled")
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        cancelSpokenBubbleHide()
        tts?.stop()
        showOnboardingControlsStep(createdPageURL: nil)
    }

    private func selectOnboardingModel(_ model: SidekickModel) {
        applySelectedModel(model)
        log("model selected: \(model.id)")
        showListeningStep()
    }

    private func showOnboardingControlsStep(createdPageURL: URL?) {
        guard isOnboardingActive else { return }
        saveOnboardingResumePoint(.controls)
        showOnboardingStep(
            SidekickOnboardingDemo.controlsText,
            animation: "GetAttention",
            choices: [
                .init(title: "Done") { [weak self] in
                    self?.completeBubbleOnboarding(createdPageURL: createdPageURL)
                },
            ]
        )
    }

    private func completeBubbleOnboarding(createdPageURL: URL?) {
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

    private func voiceKeyStatusText() -> String {
        let missing = SidekickSecrets.missingRequiredProviderNames
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
        choices: [SidekickBubbleController.Choice]
    ) {
        cancelSpokenBubbleHide()
        hideBubbleWhenSpeechFinishes = false
        spokenBubbleShownAt = nil
        syncBubbleAnchorToSidekick()
        playOnboardingAnimation(animation)
        chatBubble?.showChoicesTyping(prompt, choices: choices)
    }

    private func playOnboardingAnimation(_ name: String) {
        pendingIdle?.cancel()
        guard isSidekickHidden == false else {
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
        Sidekick setup: \(title)
        Started: \(Date())
        Command: \(commandLine)

        """
        try header.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func setupLogDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base
            .appendingPathComponent("Sidekick", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Setup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func codexInstallCommand() -> String {
        """
        set -eu
        version="\(SidekickRuntimeLocator.codexVersion)"
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
        base="$HOME/Library/Application Support/Sidekick/Runtimes/Codex/$version"
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
        cat > "$base/bin/codex" <<'SIDEKICK_CODEX'
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
        SIDEKICK_CODEX
        chmod 755 "$base/bin/codex"
        "$base/bin/codex" --help >/dev/null
        echo "ChatGPT connector installed."
        """
    }

    private static func claudeInstallCommand() -> String {
        """
        set -eu
        version="\(SidekickRuntimeLocator.claudeVersion)"
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
        base="$HOME/Library/Application Support/Sidekick/Runtimes/Claude/$version"
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

    /// Show the focused permission helper. Permissions that accept an app bundle
    /// in System Settings use the character itself as the draggable item.
    private func showPermissionDialog(
        permission: OnboardingPermission,
        doneButtonTitle: String = "Done",
        onDone: (() -> Void)? = nil
    ) {
        guard permission == .microphone else {
            showPermissionCharacterDragPrompt(
                permission: permission,
                doneButtonTitle: doneButtonTitle,
                onDone: onDone
            )
            return
        }
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

    private func showPermissionCharacterDragPrompt(
        permission: OnboardingPermission,
        doneButtonTitle: String,
        onDone: (() -> Void)?
    ) {
        permissionDrag?.hide()
        if isSidekickHidden {
            showSidekick()
        }
        syncBubbleAnchorToSidekick()
        playOnboardingAnimation(permission.animationName)
        sidekickCharacter?.windowController.permissionDragAppURL = Bundle.main.bundleURL
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsAnchor)") {
            NSWorkspace.shared.open(url)
        }
        let done = SidekickBubbleController.Choice(title: doneButtonTitle) { [weak self] in
            self?.clearPermissionCharacterDrag()
            onDone?()
        }
        chatBubble?.showChoicesTyping(
            "Drag me into \(permission.name) in System Settings.",
            choices: [done]
        )
        permissionCharacterDragClear?.cancel()
        let clear = DispatchWorkItem { [weak self] in self?.clearPermissionCharacterDrag() }
        permissionCharacterDragClear = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: clear)
    }

    private func clearPermissionCharacterDrag() {
        permissionCharacterDragClear?.cancel()
        permissionCharacterDragClear = nil
        sidekickCharacter?.windowController.permissionDragAppURL = nil
    }

    @objc private func selectVoice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        selectVoice(id: id)
    }

    private func selectVoice(id: String) {
        guard let voice = SidekickVoice.by(id: id) else { return }
        selectedVoice = voice
        UserDefaults.standard.set(id, forKey: "SidekickVoiceID")
        tts?.voiceID = id
        log("voice: \(id)")
        guard isSidekickHidden == false else { return }
        activeTTS()?.speak("It looks like you changed my voice. [chuckle] How's this?")
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        selectModel(id: id)
    }

    private func selectModel(id: String) {
        guard let model = SidekickModel.by(id: id) else { return }
        applySelectedModel(model)
        log("model selected: \(id)")
        guard isSidekickHidden == false else { return }
        if let frame = sidekickCharacter?.frame { chatBubble?.setAnchor(frame) }
        chatBubble?.showReplyForReading("Switched to \(model.displayName).")
    }

    @objc private func quitSidekick() {
        explicitQuitRequested = true
        NSApp.terminate(nil)
    }

    // MARK: - Resources

    private static func characterResourceRoot(for spec: SidekickSpec) -> URL {
        let fileRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/Characters/\(spec.resourceFolderName)")
        let cwdRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Resources/Characters/\(spec.resourceFolderName)")
        let bundleRoot = Bundle.main.resourceURL?.appending(path: "Characters/\(spec.resourceFolderName)")
        let candidates = [bundleRoot, cwdRoot, fileRoot].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appending(path: "character.json").path) } ?? fileRoot
    }

    // MARK: - Debug instrumentation

    /// With SIDEKICK_CMD_FILE set, polls a command file so the app can be driven
    /// headlessly: `ask:<text>`, `askfront:<bundle>|<url>|<text>`, `open`,
    /// `snapshot`, `outline`, `sidekick:<id>`, `ground:`, `groundshot:`, `move:`, `park:`, `state:`.
    private func startCommandChannel() {
        // Always on: the local MCP server (SidekickMCP) relays the model's tool calls
        // into this file, and debug commands use it too. Env var overrides the path.
        let env = ProcessInfo.processInfo.environment
        let path = env["SIDEKICK_CMD_FILE"] ?? env["CLIPPY_CMD_FILE"] ?? Self.defaultCommandFilePath()
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
        let directory = base.appendingPathComponent("Sidekick", isDirectory: true)
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
            } else if command == "outline" {
                showFocusedAppComponentOutlines(reason: "debug-command")
            } else if command.hasPrefix("move:") {
                moveSidekick(command: String(command.dropFirst(5)))
            } else if command.hasPrefix("park:") {
                parkClippy(command: String(command.dropFirst(5)))
            } else if command == "hide" {
                hideSidekick()
            } else if command == "show" {
                showSidekick()
            } else if command.hasPrefix("state:") {
                applyStateCommand(String(command.dropFirst(6)))
            } else if command.hasPrefix("sidekick:") {
                switchSidekick(to: String(command.dropFirst("sidekick:".count)))
            } else if command.hasPrefix("mascot:") {
                switchSidekick(to: String(command.dropFirst("mascot:".count)))
            } else if command.hasPrefix("ground:") {
                let parsed = GroundingParser.parse(String(command.dropFirst(7)))
                if isSidekickHidden == false {
                    let spoken = VoiceSpeechTags.strip(parsed.spokenText)
                    chatBubble?.showReplyForReading(spoken.isEmpty ? "(pointing)" : spoken)
                    presentGrounding(parsed.tags)
                }
            } else if command.hasPrefix("groundshot:") {
                let parsed = GroundingParser.parse(String(command.dropFirst("groundshot:".count)))
                if isSidekickHidden == false {
                    lastDesktopContext = DesktopContextSnapshot.capture()
                    let screenshotScreen = lastDesktopContext?.targetScreen() ?? screenForSidekick()
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
        if command.hasPrefix("sidekick:") || command.hasPrefix("mascot:") {
            return command
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
            setBodyScale(SidekickBodyScale(number > 10 ? number / 100 : number))
        }
    }

    private func applyStateCommand(_ command: String) {
        guard let state = AgentActivityState(rawValue: command.trimmingCharacters(in: .whitespaces)) else {
            return
        }
        log("state: \(state.rawValue)")
        playActivityState(state)
    }

    private func moveSidekick(command: String) {
        let parts = command.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else {
            return
        }
        sidekickCharacter?.windowController.move(to: CGPoint(x: parts[0], y: parts[1]), animated: true) { [weak self] in
            if let frame = self?.sidekickCharacter?.frame { self?.chatBubble?.setAnchor(frame) }
        }
    }

    private func parkClippy(command: String) {
        guard
            let edge = SidekickParkEdge(rawValue: command),
            let visibleFrame = screenForSidekick()?.visibleFrame
        else {
            return
        }
        let size = sidekickCharacter?.windowController.frame.size ?? CGSize(width: 160, height: 160)
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
        sidekickCharacter?.windowController.move(to: origin, animated: true) { [weak self] in
            if let frame = self?.sidekickCharacter?.frame { self?.chatBubble?.setAnchor(frame) }
        }
    }

    private var snapshotDirectory: String? {
        ProcessInfo.processInfo.environment["SIDEKICK_SNAPSHOT_DIR"]
            ?? ProcessInfo.processInfo.environment["CLIPPY_SNAPSHOT_DIR"]
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
        guard let data = sidekickCharacter?.snapshotPNGData() else {
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
