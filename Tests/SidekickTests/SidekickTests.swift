import AppKit
import AVFoundation
import Foundation
import Testing
@testable import SidekickCore

private func writeExecutableScript(named name: String, contents: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

private struct FakeChronicleScreenCapture: ChronicleScreenCapturing {
    func captureFrame(directory: URL, frameID: String) -> [ChronicleScreenshotFrame] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(frameID)-screen-1.jpg")
        try? Data("fake image".utf8).write(to: url)
        return [
            ChronicleScreenshotFrame(
                path: url.path,
                pixelWidth: 800,
                pixelHeight: 600,
                screenIndex: 0,
                screenFrame: ChronicleRect(x: 0, y: 0, width: 800, height: 600)
            ),
        ]
    }
}

private func pcm16Constant(amplitude: Int16, sampleCount: Int) -> Data {
    var data = Data()
    data.reserveCapacity(sampleCount * 2)
    let bitPattern = UInt16(bitPattern: amplitude)
    for _ in 0..<sampleCount {
        data.append(UInt8(bitPattern & 0xff))
        data.append(UInt8((bitPattern >> 8) & 0xff))
    }
    return data
}

private final class AutoHideProbe {
    var didFire = false
}

private extension SidekickBackgroundScreenSuggestionState {
    func with(
        enabled: Bool? = nil,
        isTurnRunning: Bool? = nil,
        isVoiceCaptureActive: Bool? = nil,
        isPushToTalkHeld: Bool? = nil,
        isTTSSpeaking: Bool? = nil,
        isPresentingChoices: Bool? = nil,
        isInputMode: Bool? = nil,
        isUserAnnotating: Bool? = nil,
        isAnnotationHoldActive: Bool? = nil,
        isOnboardingActive: Bool? = nil,
        isWorkflowRecording: Bool? = nil,
        hasGuidedTarget: Bool? = nil,
        isSidekickHidden: Bool? = nil
    ) -> SidekickBackgroundScreenSuggestionState {
        SidekickBackgroundScreenSuggestionState(
            enabled: enabled ?? self.enabled,
            isTurnRunning: isTurnRunning ?? self.isTurnRunning,
            isVoiceCaptureActive: isVoiceCaptureActive ?? self.isVoiceCaptureActive,
            isPushToTalkHeld: isPushToTalkHeld ?? self.isPushToTalkHeld,
            isTTSSpeaking: isTTSSpeaking ?? self.isTTSSpeaking,
            isPresentingChoices: isPresentingChoices ?? self.isPresentingChoices,
            isInputMode: isInputMode ?? self.isInputMode,
            isUserAnnotating: isUserAnnotating ?? self.isUserAnnotating,
            isAnnotationHoldActive: isAnnotationHoldActive ?? self.isAnnotationHoldActive,
            isOnboardingActive: isOnboardingActive ?? self.isOnboardingActive,
            isWorkflowRecording: isWorkflowRecording ?? self.isWorkflowRecording,
            hasGuidedTarget: hasGuidedTarget ?? self.hasGuidedTarget,
            isSidekickHidden: isSidekickHidden ?? self.isSidekickHidden
        )
    }
}

@Test func chronicleRecorderWritesSessionAndEvents() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sidekick-chronicle-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = SidekickChronicleRecorder(
        storageRoot: root,
        screenCapture: FakeChronicleScreenCapture(),
        now: { Date(timeIntervalSince1970: 1_000) },
        eventMonitorFactory: nil
    )

    let started = try recorder.start(timeLimitSeconds: 60)
    #expect(started.state == .recording)
    #expect(FileManager.default.fileExists(atPath: started.metadataPath))
    #expect(FileManager.default.fileExists(atPath: started.eventsPath))
    #expect(started.frameCount == 1)

    let currentStatus = try recorder.status()
    let status = try #require(currentStatus)
    #expect(status.id == started.id)
    #expect(status.eventsPath == started.eventsPath)

    let stopped = try recorder.stop()
    #expect(stopped.state == .stopped)
    #expect(stopped.eventCount >= 3)

    let events = try String(contentsOfFile: stopped.eventsPath, encoding: .utf8)
    #expect(events.contains(#""type":"recording_started""#))
    #expect(events.contains(#""type":"screen_sample""#))
    #expect(events.contains(#""type":"recording_stopped""#))
    #expect(events.contains(#""pixelWidth":800"#))
}

@Test func recordReplayMCPConfigFindsExplicitOverride() throws {
    let scriptURL = try writeExecutableScript(
        named: "fake-record-replay-mcp",
        contents: "#!/bin/sh\nexit 0\n"
    )
    defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }

    let runtime = SidekickRecordReplayMCPConfig.defaultRuntime(
        environment: ["SIDEKICK_RECORD_REPLAY_MCP": scriptURL.path]
    )
    let resolved = try #require(runtime)
    #expect(resolved.serverName == "sidekick-record-replay")
    #expect(resolved.command == scriptURL.path)
    #expect(resolved.enabledTools == ["event_stream_start", "event_stream_status", "event_stream_stop"])
}

@Test func actionQueueRunsFifoAndInterrupts() async throws {
    let queue = SidekickActionQueue()
    let first = SidekickAction(command: .setState(.thinking))
    let second = SidekickAction(command: .setState(.done))

    await queue.enqueue(first)
    await queue.enqueue(second)

    let started = await queue.startNext()
    #expect(started?.id == first.id)
    #expect(started?.status == .running)

    let stopped = await queue.stopCurrent()
    #expect(stopped?.id == first.id)
    #expect(stopped?.status == .interrupted)

    let next = await queue.startNext()
    #expect(next?.id == second.id)
}

@Test func runtimeLocatorFindsSidekickManagedExecutables() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("sidekick-runtimes-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: base) }

    let codex = SidekickRuntimeLocator.codexExecutableURL(baseDirectory: base)
    let claude = SidekickRuntimeLocator.claudeExecutableURL(baseDirectory: base)
    try FileManager.default.createDirectory(at: codex.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: codex, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: claude, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)

    #expect(SidekickRuntimeLocator.codexExecutablePath(baseDirectory: base) == codex.path)
    #expect(SidekickRuntimeLocator.claudeExecutablePath(baseDirectory: base) == claude.path)
}

@Test func codexConversationUnwrapsNPMShimToNativeExecutable() throws {
    #if arch(arm64)
    let platformPackage = "@openai/codex-darwin-arm64"
    let targetTriple = "aarch64-apple-darwin"
    #elseif arch(x86_64)
    let platformPackage = "@openai/codex-darwin-x64"
    let targetTriple = "x86_64-apple-darwin"
    #else
    return
    #endif

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sidekick-codex-shim-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let shim = root.appendingPathComponent("bin/codex")
    let native = root
        .appendingPathComponent("lib/node_modules/@openai/codex/node_modules", isDirectory: true)
        .appendingPathComponent(platformPackage, isDirectory: true)
        .appendingPathComponent("vendor", isDirectory: true)
        .appendingPathComponent(targetTriple, isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("codex", isDirectory: false)

    try FileManager.default.createDirectory(at: shim.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: native.deletingLastPathComponent(), withIntermediateDirectories: true)
    try """
    #!/usr/bin/env node
    const PLATFORM_PACKAGE_BY_TARGET = {};
    const platformPackage = "@openai/codex";
    """.write(to: shim, atomically: true, encoding: .utf8)
    try "#!/bin/sh\nexit 0\n".write(to: native, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: native.path)

    #expect(CodexConversation.resolvedExecutablePath(shim.path) == native.path)
}

@Test func localCLIConversationPassesStructuredOutputSchemaToClaude() async throws {
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-claude-schema-\(UUID().uuidString).txt")
    let scriptURL = try writeExecutableScript(
        named: "fake-claude-schema.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        log_file='\(logURL.path)'
        for arg in "$@"; do
          print -r -- "arg:$arg" >> "$log_file"
        done
        print -r -- '{"result":"Done","structured_output":{"message":"Structured","options":[]},"is_error":false,"total_cost_usd":0.0}'
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: logURL)
    }

    let conversation = LocalCLIConversation(
        binaryPath: scriptURL.path,
        allowedTools: [],
        permissionMode: "acceptEdits",
        workingDirectory: nil,
        systemPrompt: nil,
        model: nil,
        effort: nil
    )

    let turn = await conversation.sendStructured(
        "recommend actions",
        outputSchema: SidekickInvocationSuggestions.recommendationSchema
    )

    #expect(turn.text.contains(#""message":"Structured""#))

    let logged = try String(contentsOf: logURL, encoding: .utf8)
    #expect(logged.contains("arg:--json-schema"))
    #expect(logged.contains(#""required":["message","options"]"#))
    #expect(logged.contains(#""minItems":3"#))
    #expect(logged.contains("arg:recommend actions"))
}

@Test func localCLIConversationLetsClaudeReadLocalImagePathsForStructuredTurns() async throws {
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-claude-image-\(UUID().uuidString).txt")
    let scriptURL = try writeExecutableScript(
        named: "fake-claude-image.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        log_file='\(logURL.path)'
        for arg in "$@"; do
          print -r -- "arg:$arg" >> "$log_file"
        done
        print -r -- '{"result":"Done","structured_output":{"shouldShowOptions":false,"reason":"quiet screen"},"is_error":false,"total_cost_usd":0.0}'
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: logURL)
    }

    let conversation = LocalCLIConversation(
        binaryPath: scriptURL.path,
        allowedTools: [],
        permissionMode: "acceptEdits",
        workingDirectory: nil,
        systemPrompt: nil,
        model: nil,
        effort: nil
    )

    let turn = await conversation.sendStructured(
        "classify this screen",
        localImagePaths: ["/tmp/sidekick-screen.jpg"],
        outputSchema: SidekickBackgroundScreenSuggestions.wakeSchema
    )

    #expect(turn.text.contains(#""shouldShowOptions":false"#))

    let logged = try String(contentsOf: logURL, encoding: .utf8)
    #expect(logged.contains("arg:--add-dir"))
    #expect(logged.contains("arg:/tmp"))
    #expect(logged.contains("arg:--allowedTools"))
    #expect(logged.contains("arg:Read"))
    #expect(logged.contains("Use the Read tool to inspect these local screenshot image files"))
    #expect(logged.contains("/tmp/sidekick-screen.jpg"))
}

@Test func voiceContextNoteReflectsSpokenInputAndSpokenOutput() {
    // Plain typed, bubble-only turn — no voice note at all.
    #expect(SidekickAgentInstructions.voiceContextNote(inputMode: .text, speaking: false) == nil)

    // Typed but replies are spoken — only the write-for-the-ear half.
    let spokenOut = SidekickAgentInstructions.voiceContextNote(inputMode: .text, speaking: true)
    #expect(spokenOut != nil)
    #expect(spokenOut?.contains("read aloud") == true)
    #expect(spokenOut?.contains("Sidekick voice") == true)
    #expect(spokenOut?.contains("SPOKE this") == false)

    // Spoken input, silent replies — only the read-past-transcription-typos half.
    let spokenIn = SidekickAgentInstructions.voiceContextNote(inputMode: .voice, speaking: false)
    #expect(spokenIn != nil)
    #expect(spokenIn?.contains("SPOKE this") == true)
    #expect(spokenIn?.contains("transcribed") == true)
    #expect(spokenIn?.contains("read aloud") == false)

    // Full voice turn — both halves present.
    let both = SidekickAgentInstructions.voiceContextNote(inputMode: .voice, speaking: true)
    #expect(both?.contains("SPOKE this") == true)
    #expect(both?.contains("read aloud") == true)
}

@Test func desktopContextPromptBlockIncludesAppWindowScreenAndBrowser() {
    let context = DesktopContextSnapshot(
        app: .init(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 123),
        window: .init(
            title: "Example App",
            ownerName: "Google Chrome",
            ownerProcessIdentifier: 123,
            windowIdentifier: 456,
            bounds: CGRect(x: 10, y: 20, width: 800, height: 600)
        ),
        screen: .init(
            index: 1,
            appKitFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            displayBounds: CGRect(x: 0, y: 0, width: 3456, height: 2234),
            displayIdentifier: 99
        ),
        browser: .init(title: "Example App", url: "https://example.test/form")
    )

    let block = context.promptBlock

    #expect(block.contains("active app: Google Chrome (com.google.Chrome, pid 123)"))
    #expect(block.contains("active window: title \"Example App\" id 456"))
    #expect(block.contains("browser tab url: https://example.test/form"))
    #expect(block.contains("screenshot target screen: index 1"))
}

@Test func accessibilityTreePromptBlockIncludesSemanticsAndActions() {
    let tree = DesktopAccessibilityTreeSnapshot(
        appName: "Messages",
        bundleIdentifier: "com.apple.MobileSMS",
        processIdentifier: 37209,
        nodes: [
            .init(
                depth: 0,
                role: "AXWindow",
                subrole: nil,
                roleDescription: "standard window",
                title: "Messages",
                label: nil,
                value: nil,
                identifier: nil,
                focused: true,
                frame: CGRect(x: 0, y: 0, width: 900, height: 700),
                actions: []
            ),
            .init(
                depth: 1,
                role: "AXStaticText",
                subrole: nil,
                roleDescription: "text",
                title: nil,
                label: "Unread, Summary, Transaction declined at Bold Software",
                value: nil,
                identifier: "thread-summary",
                focused: nil,
                frame: CGRect(x: 12, y: 50, width: 350, height: 80),
                actions: ["AXPress", "Name:Mark as Read", "Name:Reply"]
            ),
        ],
        issue: nil
    )

    let block = tree.promptBlock

    #expect(block.contains("Current accessibility tree snapshot"))
    #expect(block.contains("source app: Messages (com.apple.MobileSMS, pid 37209)"))
    #expect(block.contains("captured AX nodes: 2"))
    #expect(block.contains("AXStaticText"))
    #expect(block.contains("Unread, Summary, Transaction declined"))
    #expect(block.contains("Name:Mark as Read"))
    #expect(block.contains("do not require OCR"))
    #expect(block.contains("primary signal"))
    #expect(block.contains("primary wake signal") == false)
}

@Test func brainMessageOrdersDesktopContextAccessibilityTreeScreenshotVoiceThenText() throws {
    let context = DesktopContextSnapshot(
        app: .init(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 123),
        window: nil,
        screen: nil,
        browser: nil
    )
    let accessibilityTree = DesktopAccessibilityTreeSnapshot(
        appName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        processIdentifier: 123,
        nodes: [
            .init(
                depth: 0,
                role: "AXWindow",
                subrole: nil,
                roleDescription: "window",
                title: "Example",
                label: nil,
                value: nil,
                identifier: nil,
                focused: true,
                frame: nil,
                actions: ["AXRaise"]
            ),
        ],
        issue: nil
    )
    let msg = SidekickAgentInstructions.brainMessage(
        text: "whats on my screen",
        screenshotPath: "/tmp/shot.png",
        screenshotPixelWidth: 3456,
        screenshotPixelHeight: 2234,
        inputMode: .voice,
        speaking: true,
        desktopContext: context,
        accessibilityTree: accessibilityTree)
    // Desktop context first, AX tree second, screenshot third, voice note fourth, user's words last.
    let contextIdx = try #require(msg.range(of: "Current desktop context")?.lowerBound)
    let axIdx = try #require(msg.range(of: "Current accessibility tree")?.lowerBound)
    let shotIdx = try #require(msg.range(of: "Current full-display screenshot")?.lowerBound)
    let voiceIdx = try #require(msg.range(of: "Voice mode")?.lowerBound)
    let textIdx = try #require(msg.range(of: "whats on my screen")?.lowerBound)
    #expect(contextIdx < axIdx)
    #expect(axIdx < shotIdx)
    #expect(shotIdx < voiceIdx)
    #expect(voiceIdx < textIdx)
    #expect(msg.contains("3456x2234 px"))
    #expect(msg.contains("active app: Google Chrome"))
    #expect(msg.contains("AXRaise"))

    // A typed, silent turn carries desktop metadata + text but no voice note.
    let quiet = SidekickAgentInstructions.brainMessage(
        text: "hello",
        screenshotPath: nil,
        screenshotPixelWidth: 0,
        screenshotPixelHeight: 0,
        inputMode: .text,
        speaking: false,
        desktopContext: context)
    #expect(quiet.contains("Voice mode") == false)
    #expect(quiet.contains("hello"))
    #expect(quiet.contains("active app: Google Chrome"))

    let guided = SidekickAgentInstructions.brainMessage(
        text: "draw on this",
        screenshotPath: "/tmp/shot.png",
        screenshotPixelWidth: 1600,
        screenshotPixelHeight: 1034,
        inputMode: .text,
        speaking: false,
        desktopContext: context,
        requiresVisualGrounding: true)
    #expect(guided.contains("Sidekick guided visual turn"))
    #expect(guided.contains("Look at the current screenshot as truth"))
    #expect(guided.contains("[POINT:x,y:label]"))
    #expect(guided.contains("[TARGET:x,y,r:label]"))
    #expect(guided.contains("[HOVER:x,y,r:label]"))
    #expect(guided.contains("[HIGHLIGHT]"))
    #expect(guided.contains("[SHAPE:line|arrow|circle|curve|polygon"))
    #expect(guided.contains("do not fake a target"))
    #expect(guided.contains("[POINT:none]") == false)
    #expect(guided.contains("[ACT]") == false)
    #expect(guided.contains("Pythagorean") == false)
}

@Test func visualGroundingRepairMessageIsGenericAndScreenshotGrounded() {
    let context = DesktopContextSnapshot(
        app: .init(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 123),
        window: nil,
        screen: nil,
        browser: .init(title: "Demo", url: "http://127.0.0.1/demo")
    )
    let msg = SidekickAgentInstructions.visualGroundingRepairMessage(
        originalUserText: "draw on this",
        previousAssistantText: "Here is a text-only explanation.",
        screenshotPath: "/tmp/shot.png",
        screenshotPixelWidth: 1600,
        screenshotPixelHeight: 1034,
        desktopContext: context
    )
    #expect(msg.contains("Visual grounding repair"))
    #expect(msg.contains("had no renderable visual grounding tag"))
    #expect(msg.contains("/tmp/shot.png (1600x1034 px)"))
    #expect(msg.contains("[POINT]"))
    #expect(msg.contains("[TARGET]/[HOVER]"))
    #expect(msg.contains("[HIGHLIGHT]"))
    #expect(msg.contains("[SHAPE]"))
    #expect(msg.contains("[ACT]") == false)
    #expect(msg.contains("Do not use shape, highlight, target, hover, or animation tags.") == false)
    #expect(msg.contains("Pythagorean") == false)
}

@Test func richVisualGroundingResponsesKeepRenderableTags() {
    let drawing = GroundingParser.parse("""
    I circled the target and outlined the triangle. \
    [SHAPE:circle:520,170;560,170:red target] \
    [SHAPE:polygon:930,470;1120,470;1120,280:right triangle]
    """)
    let drawingTags = drawing.tags
    #expect(drawingTags.count == 2)
    #expect(drawingTags.allSatisfy { $0.isRenderableVisual })
    #expect(drawingTags.allSatisfy {
        if case .shape = $0 { return true }
        return false
    })

    let squares = GroundingParser.parse("""
    I drew the three square areas in order. \
    [SHAPE:polygon:760,470;930,470;930,640;760,640:left square] \
    [SHAPE:polygon:1120,280;1290,280;1290,470;1120,470:right square] \
    [SHAPE:polygon:930,470;1120,470;1120,660;930,660:hypotenuse square]
    """)
    let squareTags = squares.tags
    #expect(squareTags.count == 3)
    #expect(squareTags.allSatisfy { $0.isRenderableVisual })

    let form = GroundingParser.parse("""
    Type in the notes box; when it looks right, say continue. \
    [HIGHLIGHT:208,397,70:notes area] [POINT:732,590:submit demo]
    """)
    let formTags = form.tags
    #expect(formTags.count == 2)
    #expect(formTags.allSatisfy { $0.isRenderableVisual })
    #expect(formTags.contains {
        if case .highlight = $0 { return true }
        return false
    })
    #expect(formTags.contains {
        if case .point = $0 { return true }
        return false
    })
}

@Test func guidedTargetFollowUpMessageMatchesClickToAdvanceContract() {
    let context = DesktopContextSnapshot(
        app: .init(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 123),
        window: nil,
        screen: nil,
        browser: .init(title: "Demo", url: "http://127.0.0.1/demo")
    )
    let msg = SidekickAgentInstructions.guidedTargetFollowUpMessage(
        label: "Add button",
        trigger: "clicked",
        triggerPointX: 420,
        triggerPointY: 360,
        round: 2,
        remainingRounds: 0,
        overallGoal: "Guide me through the demo.",
        previousInstruction: "Click Add button.",
        completedSteps: ["Add button"],
        screenshotPath: "/tmp/shot.png",
        screenshotPixelWidth: 1600,
        screenshotPixelHeight: 1034,
        desktopContext: context
    )
    #expect(msg.contains("Guided target follow-up"))
    #expect(msg.contains("Overall user goal"))
    #expect(msg.contains("Guide me through the demo."))
    #expect(msg.contains("Previous instruction"))
    #expect(msg.contains("Click Add button."))
    #expect(msg.contains("Completed guided steps"))
    #expect(msg.contains("Add button"))
    #expect(msg.contains("clicked the guided target \"Add button\""))
    #expect(msg.contains("/tmp/shot.png (1600x1034 px)"))
    #expect(msg.contains("remaining click-to-advance turns after this response: 0"))
    #expect(msg.contains("Look at the fresh screenshot above as truth"))
    #expect(msg.contains("do not re-emit that same opener"))
    #expect(msg.contains("Choose the right visual by intent"))
    #expect(msg.contains("If the task is complete"))
    #expect(msg.contains("[TARGET:x,y,r:label]"))
    #expect(msg.contains("[HOVER:x,y,r:label]"))
    #expect(msg.contains("[HIGHLIGHT]"))
    #expect(msg.contains("[SHAPE:arrow]"))
    #expect(msg.contains("Do not emit [POINT:none]"))
}

@Test func screenshotPolicyCapturesOnlyScreenSpecificTurns() {
    #expect(SidekickAgentInstructions.shouldAttachScreenshot(text: "Say exactly: perf ok.", inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldAttachScreenshot(text: "what's on my screen", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldAttachScreenshot(text: "highlight this button", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldAttachScreenshot(text: "fix that", inputMode: .voice))
    #expect(SidekickAgentInstructions.shouldAttachScreenshot(text: "summarize the docs", inputMode: .voice) == false)

    let messagesContext = DesktopContextSnapshot(
        app: .init(name: "Messages", bundleIdentifier: "com.apple.MobileSMS", processIdentifier: 123),
        window: .init(
            title: nil,
            ownerName: "Messages",
            ownerProcessIdentifier: 123,
            windowIdentifier: 456,
            bounds: CGRect(x: 0, y: 0, width: 900, height: 700)
        ),
        screen: nil,
        browser: nil
    )
    #expect(SidekickAgentInstructions.shouldAttachScreenshot(
        text: "its in my downloads now can u do it",
        inputMode: .text,
        desktopContext: messagesContext
    ) == false)
    #expect(SidekickAgentInstructions.shouldShareDesktopContext(
        text: "its in my downloads now can u do it",
        inputMode: .text,
        desktopContext: messagesContext
    ))
    #expect(SidekickAgentInstructions.shouldAttachScreenshot(
        text: "do this",
        inputMode: .text,
        desktopContext: messagesContext
    ) == false)
    #expect(SidekickAgentInstructions.shouldShareDesktopContext(
        text: "this document is in downloads now",
        inputMode: .text,
        desktopContext: messagesContext
    ))
    #expect(SidekickAgentInstructions.shouldAttachScreenshot(
        text: "what's on my screen",
        inputMode: .text,
        desktopContext: messagesContext
    ))
    #expect(SidekickAgentInstructions.shouldShareDesktopContext(
        text: "point to the send button",
        inputMode: .text,
        desktopContext: messagesContext
    ))
    #expect(SidekickAgentInstructions.shouldAttachScreenshot(
        text: "point to the send button",
        inputMode: .text,
        desktopContext: messagesContext
    ))
}

@Test func fullDiskAccessProbeTargetsLocalAppDatabases() {
    let home = URL(fileURLWithPath: "/Users/example")
    let paths = FullDiskAccessPermission.databaseProbeURLs(home: home).map(\.path)
    #expect(paths.contains("/Users/example/Library/Messages/chat.db"))
    #expect(paths.contains("/Users/example/Library/Safari/History.db"))
    #expect(paths.contains("/Users/example/Library/Application Support/com.apple.TCC/TCC.db"))
}

@Test func computerControlPolicyRoutesGuiWorkToCodexLane() {
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "fill out this application form", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "fill it out right away", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "fill out this form with my name, then draw on it", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "apply to this job in the browser", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "click the blue button", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "Guide me to click the Start demo button. Mark it as the click target and continue after I click it.", inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "Highlight the Notes area for manual typing and point at the Submit demo button. Do not click anything.", inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "point at the Submit demo button", inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "type this into the page", inputMode: .voice))
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "hover over that menu", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "hover a ring over this button", inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "summarize the docs", inputMode: .voice) == false)
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: "what's on my screen", inputMode: .text) == false)
}

@Test func visualGroundingPolicyKeepsPointerWorkOnSelectedModelLane() {
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "highlight this button", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "draw an arrow on the page", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "Can you draw my screen to explain this?", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "draw over this page", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "fill out this form with my name, then draw on it", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "draw", inputMode: .voice))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "point at the menu", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "circle this", inputMode: .voice))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "Now explain the square areas on the triangle by drawing the three squares in order, then leave the drawing visible.", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "Highlight the Notes area for manual typing and point at the Submit demo button. Do not click anything.", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "Guide me to click the Start demo button. Mark it as the click target and continue after I click it.", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: "draw a logo", inputMode: .text) == false)

    #expect(SidekickAgentInstructions.shouldUseCodexToolLane(text: "highlight this button", inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldUseCodexToolLane(text: "Can you draw my screen to explain this?", inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldUseCodexToolLane(text: "show me where to click", inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldUseCodexToolLane(text: "draw an arrow on the page", inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldUseCodexToolLane(text: "fill out this form", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseCodexToolLane(text: "fill out this form with my name, then draw on it", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseCodexToolLane(text: "record my workflow and turn it into a reusable skill", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseCodexToolLane(text: "create a skill from this video", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseRecordReplayTool(text: "watch me do this task and make a skill", inputMode: .text))
    #expect(SidekickAgentInstructions.shouldUseCodexToolLane(text: "summarize the docs", inputMode: .text) == false)
}

@Test func computerUsePromptDisablesSecondCursorForVisibleActions() {
    #expect(SidekickAgentInstructions.systemPrompt.contains("computer-control cursor overlay is disabled in Sidekick"))
    #expect(SidekickAgentInstructions.systemPrompt.contains("The visible pointer is the active"))
    #expect(SidekickAgentInstructions.systemPrompt.contains("[POINT:x,y:label]"))
    #expect(SidekickAgentInstructions.systemPrompt.contains("[TARGET:x,y,r:label]"))
    #expect(SidekickAgentInstructions.systemPrompt.contains("[HOVER:x,y,r:label]"))
    #expect(SidekickAgentInstructions.systemPrompt.contains("[HIGHLIGHT:x,y,r:label]"))
    #expect(SidekickAgentInstructions.systemPrompt.contains("[SHAPE:line|arrow|circle|curve|polygon"))
    #expect(SidekickAgentInstructions.systemPrompt.contains("[ACT") == false)
    #expect(SidekickAgentInstructions.systemPrompt.contains("Pythagorean") == false)
}

@Test func activeCharacterPromptDoesNotUseProductNameAsPersona() {
    let prompt = SidekickAgentInstructions.systemPrompt(for: .rover)
    #expect(prompt.contains("Product name: Sidekick."))
    #expect(prompt.contains("Visible character: Rover."))
    #expect(prompt.contains("Do not introduce yourself as \"Sidekick\""))
    #expect(prompt.contains("Speak as Rover, not as the product name Sidekick."))
    #expect(prompt.contains("You are Sidekick") == false)
}

@Test func codexConversationResumesTheSameThreadAcrossTurns() async throws {
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-codex-log-\(UUID().uuidString).txt")
    let scriptURL = try writeExecutableScript(
        named: "fake-codex.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        log_file='\(logURL.path)'
        print -r -- "args:$*" >> "$log_file"
        turn_count=0
        request_id() {
          print -r -- "$1" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p'
        }
        while IFS= read -r line; do
          print -r -- "$line" >> "$log_file"
          id="$(request_id "$line")"
          if [[ "$line" == *'"method":"initialize"'* ]]; then
            print -r -- '{"id":'${id}',"result":{}}'
          elif [[ "$line" == *'thread/start'* || "$line" == *'thread\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"thread":{"id":"THREAD-123"}}}'
          elif [[ "$line" == *'turn/start'* || "$line" == *'turn\\/start'* ]]; then
            turn_count=$((turn_count + 1))
            turn_id="TURN-${turn_count}"
            text="ALPHA"
            if [[ "$turn_count" == "2" ]]; then text="BETA"; fi
            print -r -- '{"id":'${id}',"result":{"turn":{"id":"'${turn_id}'","items":[],"itemsView":"full","status":"inProgress","error":null,"startedAt":0,"completedAt":null,"durationMs":null}}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-123","turnId":"'${turn_id}'","itemId":"ITEM-'${turn_count}'","delta":"'${text}'"}}'
            print -r -- '{"method":"item/completed","params":{"threadId":"THREAD-123","turnId":"'${turn_id}'","completedAtMs":0,"item":{"type":"agentMessage","id":"ITEM-'${turn_count}'","text":"'${text}'","phase":null,"memoryCitation":null}}}'
            print -r -- '{"method":"turn/completed","params":{"threadId":"THREAD-123","turn":{"id":"'${turn_id}'","items":[],"itemsView":"full","status":"completed","error":null,"startedAt":0,"completedAt":0,"durationMs":1}}}'
          fi
        done
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: logURL)
    }

    let conversation = CodexConversation(
        binaryPath: scriptURL.path,
        model: "gpt-5.5",
        effort: "minimal",
        workingDirectory: nil,
        systemPrompt: nil,
        diagnosticsLogURL: nil
    )

    let first = await conversation.send("first turn")
    let second = await conversation.send("second turn")

    #expect(first.text == "ALPHA")
    #expect(second.text == "BETA")

    let logged = try String(contentsOf: logURL, encoding: .utf8)
    let lines = logged.split(whereSeparator: \.isNewline).map(String.init)
    #expect(lines.first?.contains("app-server --stdio") == true)
    #expect(lines.first?.contains("first turn") == false)
    #expect(lines.filter { $0.contains("thread/start") || $0.contains("thread\\/start") }.count == 1)
    #expect(lines.filter { $0.contains("turn/start") || $0.contains("turn\\/start") }.count == 2)
    #expect(logged.contains(#""threadId":"THREAD-123""#))
    #expect(logged.contains("first turn"))
    #expect(logged.contains("second turn"))
}

@Test func codexConversationPrepareOpensThreadBeforeFirstTurn() async throws {
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-codex-prepare-\(UUID().uuidString).txt")
    let scriptURL = try writeExecutableScript(
        named: "fake-codex-prepare.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        log_file='\(logURL.path)'
        print -r -- "args:$*" >> "$log_file"
        request_id() {
          print -r -- "$1" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p'
        }
        while IFS= read -r line; do
          print -r -- "$line" >> "$log_file"
          id="$(request_id "$line")"
          if [[ "$line" == *'"method":"initialize"'* ]]; then
            print -r -- '{"id":'${id}',"result":{}}'
          elif [[ "$line" == *'thread/start'* || "$line" == *'thread\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"thread":{"id":"THREAD-PREPARED"}}}'
          elif [[ "$line" == *'turn/start'* || "$line" == *'turn\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"turn":{"id":"TURN-PREPARED","items":[],"itemsView":"full","status":"inProgress","error":null,"startedAt":0,"completedAt":null,"durationMs":null}}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-PREPARED","turnId":"TURN-PREPARED","itemId":"ITEM-PREPARED","delta":"READY"}}'
            print -r -- '{"method":"item/completed","params":{"threadId":"THREAD-PREPARED","turnId":"TURN-PREPARED","completedAtMs":0,"item":{"type":"agentMessage","id":"ITEM-PREPARED","text":"READY","phase":null,"memoryCitation":null}}}'
            print -r -- '{"method":"turn/completed","params":{"threadId":"THREAD-PREPARED","turn":{"id":"TURN-PREPARED","items":[],"itemsView":"full","status":"completed","error":null,"startedAt":0,"completedAt":0,"durationMs":1}}}'
          fi
        done
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: logURL)
    }

    let conversation = CodexConversation(
        binaryPath: scriptURL.path,
        model: "gpt-5.5",
        effort: "minimal",
        workingDirectory: nil,
        systemPrompt: nil,
        diagnosticsLogURL: nil
    )

    await conversation.prepare()
    let turn = await conversation.send("first prepared turn")

    #expect(turn.text == "READY")

    let logged = try String(contentsOf: logURL, encoding: .utf8)
    let lines = logged.split(whereSeparator: \.isNewline).map(String.init)
    #expect(logged.contains(#""threadId":"THREAD-PREPARED""#))
    #expect(logged.contains("first prepared turn"))
    #expect(lines.filter { $0.contains("thread/start") || $0.contains("thread\\/start") }.count == 1)
    #expect(lines.filter { $0.contains("turn/start") || $0.contains("turn\\/start") }.count == 1)
}

@Test func codexConversationAttachesLocalImagesToTurnStart() async throws {
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-codex-local-image-\(UUID().uuidString).txt")
    let scriptURL = try writeExecutableScript(
        named: "fake-codex-local-image.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        log_file='\(logURL.path)'
        request_id() {
          print -r -- "$1" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p'
        }
        while IFS= read -r line; do
          print -r -- "$line" >> "$log_file"
          id="$(request_id "$line")"
          if [[ "$line" == *'"method":"initialize"'* ]]; then
            print -r -- '{"id":'${id}',"result":{}}'
          elif [[ "$line" == *'thread/start'* || "$line" == *'thread\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"thread":{"id":"THREAD-IMAGE"}}}'
          elif [[ "$line" == *'turn/start'* || "$line" == *'turn\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"turn":{"id":"TURN-IMAGE","items":[],"itemsView":"full","status":"inProgress","error":null,"startedAt":0,"completedAt":null,"durationMs":null}}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-IMAGE","turnId":"TURN-IMAGE","itemId":"ITEM-IMAGE","delta":"SEEN"}}'
            print -r -- '{"method":"item/completed","params":{"threadId":"THREAD-IMAGE","turnId":"TURN-IMAGE","completedAtMs":0,"item":{"type":"agentMessage","id":"ITEM-IMAGE","text":"SEEN","phase":null,"memoryCitation":null}}}'
            print -r -- '{"method":"turn/completed","params":{"threadId":"THREAD-IMAGE","turn":{"id":"TURN-IMAGE","items":[],"itemsView":"full","status":"completed","error":null,"startedAt":0,"completedAt":0,"durationMs":1}}}'
          fi
        done
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: logURL)
    }

    let conversation = CodexConversation(
        binaryPath: scriptURL.path,
        model: "gpt-5.5",
        effort: "minimal",
        workingDirectory: nil,
        systemPrompt: nil,
        diagnosticsLogURL: nil
    )

    let turn = await conversation.send("look at the screen", localImagePaths: ["/tmp/sidekick-screen.jpg"])

    #expect(turn.text == "SEEN")

    let logged = try String(contentsOf: logURL, encoding: .utf8)
    #expect(logged.contains(#""type":"text""#))
    #expect(logged.contains(#""text":"look at the screen""#))
    #expect(logged.contains(#""type":"localImage""#))
    #expect(
        logged.contains(#""path":"/tmp/sidekick-screen.jpg""#)
            || logged.contains(#""path":"\/tmp\/sidekick-screen.jpg""#)
    )
}

@Test func richReplyParsesMarkdownImageCardsAndSourceLinks() {
    let reply = SidekickRichReply.parse("""
    Here are two visual references.
    ![Mars rover wheel](https://images.example.test/rover-wheel.jpg)
    Source: [NASA image page](https://www.nasa.gov/rover-wheel)

    Read the background from [JPL](https://www.jpl.nasa.gov/missions).
    """)

    #expect(reply.text == "Here are two visual references.\n\nRead the background from JPL.")
    #expect(reply.imageCards == [
        .init(
            caption: "Mars rover wheel",
            imageURLString: "https://images.example.test/rover-wheel.jpg",
            sourceTitle: "NASA image page",
            sourceURLString: "https://www.nasa.gov/rover-wheel"
        ),
    ])
    #expect(reply.citations == [
        .init(title: "NASA image page", urlString: "https://www.nasa.gov/rover-wheel"),
        .init(title: "JPL", urlString: "https://www.jpl.nasa.gov/missions"),
    ])
}

@Test @MainActor func sidekickBubbleCreatesImageCardsForRichReply() {
    let bubble = SidekickBubbleController()
    defer { bubble.hide() }

    bubble.showReply("""
    Look at this reference.
    ![Local sample](file:///tmp/sidekick-rich-card.png)
    Source: [Local source](file:///tmp/sidekick-rich-card-source)
    """)

    #expect(bubble.debugRichImageCardCount == 1)
    #expect(bubble.debugCitationText == "")
}

@Test func sidekickAgentInstructionsExposeRichImageCardContract() {
    #expect(SidekickAgentInstructions.systemPrompt.contains("Rich image answers"))
    #expect(SidekickAgentInstructions.systemPrompt.contains("![short caption](direct-image-url-or-local-file-path)"))
    #expect(SidekickAgentInstructions.systemPrompt.contains("Source: [Site name](page-url)"))
}

@Test func codexConversationPassesStructuredOutputSchemaToTurnStart() async throws {
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-codex-schema-\(UUID().uuidString).txt")
    let scriptURL = try writeExecutableScript(
        named: "fake-codex-schema.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        log_file='\(logURL.path)'
        request_id() {
          print -r -- "$1" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p'
        }
        while IFS= read -r line; do
          print -r -- "$line" >> "$log_file"
          id="$(request_id "$line")"
          if [[ "$line" == *'"method":"initialize"'* ]]; then
            print -r -- '{"id":'${id}',"result":{}}'
          elif [[ "$line" == *'thread/start'* || "$line" == *'thread\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"thread":{"id":"THREAD-SCHEMA"}}}'
          elif [[ "$line" == *'turn/start'* || "$line" == *'turn\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"turn":{"id":"TURN-SCHEMA","items":[],"itemsView":"full","status":"inProgress","error":null,"startedAt":0,"completedAt":null,"durationMs":null}}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-SCHEMA","turnId":"TURN-SCHEMA","itemId":"ITEM-SCHEMA","delta":"{\\"message\\":\\"Need a hand?\\",\\"options\\":[{\\"title\\":\\"Read it\\",\\"prompt\\":\\"Read this screen.\\"}]}"}}'
            print -r -- '{"method":"item/completed","params":{"threadId":"THREAD-SCHEMA","turnId":"TURN-SCHEMA","completedAtMs":0,"item":{"type":"agentMessage","id":"ITEM-SCHEMA","text":"{\\"message\\":\\"Need a hand?\\",\\"options\\":[{\\"title\\":\\"Read it\\",\\"prompt\\":\\"Read this screen.\\"}]}","phase":null,"memoryCitation":null}}}'
            print -r -- '{"method":"turn/completed","params":{"threadId":"THREAD-SCHEMA","turn":{"id":"TURN-SCHEMA","items":[],"itemsView":"full","status":"completed","error":null,"startedAt":0,"completedAt":0,"durationMs":1}}}'
          fi
        done
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: logURL)
    }

    let conversation = CodexConversation(
        binaryPath: scriptURL.path,
        model: "gpt-5.5",
        effort: "minimal",
        workingDirectory: nil,
        systemPrompt: nil,
        diagnosticsLogURL: nil
    )

    let turn = await conversation.sendStructured(
        "recommend actions",
        localImagePaths: ["/tmp/sidekick-screen.jpg"],
        outputSchema: SidekickInvocationSuggestions.recommendationSchema
    )

    #expect(turn.text.contains(#""message":"Need a hand?""#))

    let logged = try String(contentsOf: logURL, encoding: .utf8)
    #expect(logged.contains(#""outputSchema":{"#))
    #expect(logged.contains(#""type":"object""#))
    #expect(logged.contains(#""required":["message","options"]"#))
    #expect(logged.contains(#""minItems":3"#))
    #expect(logged.contains(#""type":"localImage""#))
}

@Test func computerUseMCPConfigPrefersExplicitCuaDriver() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-cua-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cua = tempDir.appendingPathComponent("cua-driver")
    FileManager.default.createFile(atPath: cua.path, contents: Data("#!/bin/sh\n".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cua.path)

    let runtime = ComputerUseMCPConfig.defaultRuntime(environment: ["SIDEKICK_CUA_DRIVER": cua.path])
    #expect(runtime?.serverName == "cua-driver")
    #expect(runtime?.command == cua.path)
    #expect(runtime?.args == ["mcp", "--no-daemon-relaunch", "--no-overlay"])
    #expect(runtime?.enabledTools.contains("drag") == true)
    #expect(runtime?.enabledTools.contains("move_cursor") == false)
    #expect(runtime?.enabledTools.contains("set_agent_cursor_style") == false)
    #expect(runtime?.enabledTools.contains("get_agent_cursor_state") == false)
    #expect(runtime?.enabledTools.contains("zoom") == true)
    #expect(runtime?.enabledTools.contains("screenshot") == false)
    let overrides = ComputerUseMCPConfig.codexConfigOverrides(for: [try #require(runtime)])
    #expect(overrides.contains { $0.contains("mcp_servers.cua-driver.command") && $0.contains(cua.path) })
    #expect(overrides.contains { $0.contains("mcp_servers.cua-driver.enabled_tools") && $0.contains("get_window_state") })
}

@Test func computerUseMCPConfigPrefersBundledHelperOverExternalInstall() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-bundled-cua-\(UUID().uuidString)", isDirectory: true)
    let macOSDir = tempDir.appendingPathComponent("Contents/MacOS", isDirectory: true)
    let helpersDir = tempDir.appendingPathComponent("Contents/Helpers", isDirectory: true)
    try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: helpersDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let helper = helpersDir.appendingPathComponent(ComputerUseMCPConfig.bundledHelperName)
    FileManager.default.createFile(atPath: helper.path, contents: Data("#!/bin/sh\n".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

    let runtime = ComputerUseMCPConfig.defaultRuntime(
        environment: [:],
        executableDirectory: macOSDir.path,
        workingDirectory: tempDir.path
    )

    let resolved = try #require(runtime)
    #expect(resolved.serverName == "cua-driver")
    #expect(resolved.command == helper.path)
    #expect(resolved.args == ["mcp", "--no-daemon-relaunch", "--no-overlay"])
}

@Test func codexConversationWiresCuaAndAnnotationMCPServers() async throws {
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-codex-mcp-\(UUID().uuidString).txt")
    let scriptURL = try writeExecutableScript(
        named: "fake-codex-mcp.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        log_file='\(logURL.path)'
        print -r -- "$0 $*" >> "$log_file"
        request_id() {
          print -r -- "$1" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p'
        }
        while IFS= read -r line; do
          print -r -- "$line" >> "$log_file"
          id="$(request_id "$line")"
          if [[ "$line" == *'"method":"initialize"'* ]]; then
            print -r -- '{"id":'${id}',"result":{}}'
          elif [[ "$line" == *'thread/start'* || "$line" == *'thread\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"thread":{"id":"THREAD-MCP"}}}'
          elif [[ "$line" == *'turn/start'* || "$line" == *'turn\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"turn":{"id":"TURN-MCP","items":[],"itemsView":"full","status":"inProgress","error":null,"startedAt":0,"completedAt":null,"durationMs":null}}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-MCP","turnId":"TURN-MCP","itemId":"ITEM-MCP","delta":"OK"}}'
            print -r -- '{"method":"item/completed","params":{"threadId":"THREAD-MCP","turnId":"TURN-MCP","completedAtMs":0,"item":{"type":"agentMessage","id":"ITEM-MCP","text":"OK","phase":null,"memoryCitation":null}}}'
            print -r -- '{"method":"turn/completed","params":{"threadId":"THREAD-MCP","turn":{"id":"TURN-MCP","items":[],"itemsView":"full","status":"completed","error":null,"startedAt":0,"completedAt":0,"durationMs":1}}}'
          fi
        done
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: logURL)
    }

    let conversation = CodexConversation(
        binaryPath: scriptURL.path,
        model: "gpt-5.5",
        effort: "minimal",
        workingDirectory: nil,
        systemPrompt: nil,
        computerUseRuntime: MCPServerRuntime(serverName: "cua-driver", command: "/tmp/cua-driver", args: ["mcp"], enabledTools: ["click"]),
        annotationRuntime: MCPServerRuntime(serverName: "sidekick-annotation", command: "/tmp/SidekickMCP", enabledTools: ["annotate"]),
        recordReplayRuntime: MCPServerRuntime(serverName: "sidekick-record-replay", command: "/tmp/SidekickRecordReplayMCP", enabledTools: ["event_stream_start", "event_stream_status", "event_stream_stop"]),
        diagnosticsLogURL: nil
    )

    let turn = await conversation.send("use tools")
    #expect(turn.text == "OK")

    let logged = try String(contentsOf: logURL, encoding: .utf8)
    #expect(logged.contains("mcp_servers.cua-driver.command"))
    #expect(logged.contains("mcp_servers.sidekick-annotation.command"))
    #expect(logged.contains("mcp_servers.sidekick-record-replay.command"))
    #expect(logged.contains(#""cua-driver""#))
    #expect(logged.contains(#""sidekick-annotation""#))
    #expect(logged.contains(#""sidekick-record-replay""#))
    #expect(logged.contains(#""enabled_tools":["click"]"#))
    #expect(logged.contains(#""enabled_tools":["annotate"]"#))
    #expect(logged.contains(#""event_stream_start""#))
}

@Test func codexConversationStreamYieldsAgentMessageBeforeTurnExit() async throws {
    let scriptURL = try writeExecutableScript(
        named: "fake-codex-stream.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        request_id() {
          print -r -- "$1" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p'
        }
        while IFS= read -r line; do
          id="$(request_id "$line")"
          if [[ "$line" == *'"method":"initialize"'* ]]; then
            print -r -- '{"id":'${id}',"result":{}}'
          elif [[ "$line" == *'thread/start'* || "$line" == *'thread\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"thread":{"id":"THREAD-STREAM"}}}'
          elif [[ "$line" == *'turn/start'* || "$line" == *'turn\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"turn":{"id":"TURN-STREAM","items":[],"itemsView":"full","status":"inProgress","error":null,"startedAt":0,"completedAt":null,"durationMs":null}}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-STREAM","turnId":"TURN-STREAM","itemId":"ITEM-STREAM","delta":"EARLY "}}'
            sleep 1
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-STREAM","turnId":"TURN-STREAM","itemId":"ITEM-STREAM","delta":"STREAM"}}'
            print -r -- '{"method":"item/completed","params":{"threadId":"THREAD-STREAM","turnId":"TURN-STREAM","completedAtMs":0,"item":{"type":"agentMessage","id":"ITEM-STREAM","text":"EARLY STREAM","phase":null,"memoryCitation":null}}}'
            print -r -- '{"method":"turn/completed","params":{"threadId":"THREAD-STREAM","turn":{"id":"TURN-STREAM","items":[],"itemsView":"full","status":"completed","error":null,"startedAt":0,"completedAt":0,"durationMs":1}}}'
          fi
        done
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
    }

    let conversation = CodexConversation(
        binaryPath: scriptURL.path,
        model: "gpt-5.5",
        effort: "minimal",
        workingDirectory: nil,
        systemPrompt: nil,
        diagnosticsLogURL: nil
    )

    var iterator = conversation.stream("stream me").makeAsyncIterator()
    var statuses: [String] = []
    var firstPartial: String?
    streamLoop: while let chunk = await iterator.next() {
        switch chunk {
        case .status(let status):
            statuses.append(status)
        case .partial(let text), .partialMessage(text: let text, id: _):
            firstPartial = text
            break streamLoop
        case .final:
            Issue.record("Expected Codex app-server agentMessage delta to arrive before the completed item.")
            return
        }
    }

    #expect(statuses.contains("Thinking"))
    #expect(statuses.contains("Opening the Sidekick thread"))
    #expect(statuses.contains("Sending the turn"))
    #expect(firstPartial == "EARLY ")
}

@Test func codexConversationStreamsEachAgentMessageItemSeparately() async throws {
    let scriptURL = try writeExecutableScript(
        named: "fake-codex-multi-message-stream.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        request_id() {
          print -r -- "$1" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p'
        }
        while IFS= read -r line; do
          id="$(request_id "$line")"
          if [[ "$line" == *'"method":"initialize"'* ]]; then
            print -r -- '{"id":'${id}',"result":{}}'
          elif [[ "$line" == *'thread/start'* || "$line" == *'thread\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"thread":{"id":"THREAD-MULTI"}}}'
          elif [[ "$line" == *'turn/start'* || "$line" == *'turn\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"turn":{"id":"TURN-MULTI","items":[],"itemsView":"full","status":"inProgress","error":null,"startedAt":0,"completedAt":null,"durationMs":null}}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-MULTI","turnId":"TURN-MULTI","itemId":"MSG-1","delta":"First "}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-MULTI","turnId":"TURN-MULTI","itemId":"MSG-1","delta":"note."}}'
            print -r -- '{"method":"item/completed","params":{"threadId":"THREAD-MULTI","turnId":"TURN-MULTI","completedAtMs":0,"item":{"type":"agentMessage","id":"MSG-1","text":"First note.","phase":null,"memoryCitation":null}}}'
            print -r -- '{"method":"item/completed","params":{"threadId":"THREAD-MULTI","turnId":"TURN-MULTI","completedAtMs":0,"item":{"type":"toolCall","id":"TOOL-1","name":"observe.screen"}}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-MULTI","turnId":"TURN-MULTI","itemId":"MSG-2","delta":"Second "}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-MULTI","turnId":"TURN-MULTI","itemId":"MSG-2","delta":"note."}}'
            print -r -- '{"method":"item/completed","params":{"threadId":"THREAD-MULTI","turnId":"TURN-MULTI","completedAtMs":0,"item":{"type":"agentMessage","id":"MSG-2","text":"Second note.","phase":null,"memoryCitation":null}}}'
            print -r -- '{"method":"turn/completed","params":{"threadId":"THREAD-MULTI","turn":{"id":"TURN-MULTI","items":[],"itemsView":"full","status":"completed","error":null,"startedAt":0,"completedAt":0,"durationMs":1}}}'
          fi
        done
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
    }

    let conversation = CodexConversation(
        binaryPath: scriptURL.path,
        model: "gpt-5.5",
        effort: "minimal",
        workingDirectory: nil,
        systemPrompt: nil,
        diagnosticsLogURL: nil
    )

    var partials: [(String, String)] = []
    var finalText: String?
    for await chunk in conversation.stream("stream separately") {
        switch chunk {
        case .status, .partial:
            break
        case .partialMessage(text: let text, id: let id):
            partials.append((id, text))
        case .final(let turn):
            finalText = turn.text
        }
    }

    #expect(partials.map(\.0) == ["MSG-1", "MSG-1", "MSG-2", "MSG-2"])
    #expect(partials.map(\.1) == ["First ", "First note.", "Second ", "Second note."])
    #expect(finalText == "Second note.")
}

@Test func codexConversationStreamCancellationTerminatesTheChildProcess() async throws {
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-codex-cancel-\(UUID().uuidString).txt")
    let scriptURL = try writeExecutableScript(
        named: "fake-codex-cancel.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        log_file='\(logURL.path)'
        trap 'print -- "terminated" >> "$log_file"; exit 0' TERM INT
        print -- "started" >> "$log_file"
        request_id() {
          print -r -- "$1" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p'
        }
        while IFS= read -r line; do
          id="$(request_id "$line")"
          if [[ "$line" == *'"method":"initialize"'* ]]; then
            print -r -- '{"id":'${id}',"result":{}}'
          elif [[ "$line" == *'thread/start'* || "$line" == *'thread\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"thread":{"id":"THREAD-CANCEL"}}}'
          elif [[ "$line" == *'turn/start'* || "$line" == *'turn\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"turn":{"id":"TURN-CANCEL","items":[],"itemsView":"full","status":"inProgress","error":null,"startedAt":0,"completedAt":null,"durationMs":null}}}'
            sleep 30
          fi
        done
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: logURL)
    }

    let conversation = CodexConversation(
        binaryPath: scriptURL.path,
        model: "gpt-5.5",
        effort: "minimal",
        workingDirectory: nil,
        systemPrompt: nil,
        diagnosticsLogURL: nil
    )

    let task = Task {
        for await _ in conversation.stream("cancel me") {
        }
    }
    // Wait until the fake codex has actually started (it writes "started") before
    // cancelling — a fixed sleep races its startup under full-suite load.
    let startDeadline = Date().addingTimeInterval(5)
    while Date() < startDeadline {
        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        if log.contains("started") { break }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    task.cancel()
    _ = await task.result

    let deadline = Date().addingTimeInterval(10)
    var log = ""
    while Date() < deadline {
        log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        if log.contains("terminated") {
            break
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    #expect(log.contains("started"))
    #expect(log.contains("terminated"))
}

@Test func codexConversationPersistsAppServerStderrDiagnostics() async throws {
    let diagnosticsURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sidekick-codex-diagnostics-\(UUID().uuidString).log")
    let scriptURL = try writeExecutableScript(
        named: "fake-codex-stderr.zsh",
        contents: """
        #!/bin/zsh
        set -eu
        print -u2 -- "cua-driver: failed to initialize accessibility session"
        request_id() {
          print -r -- "$1" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p'
        }
        while IFS= read -r line; do
          id="$(request_id "$line")"
          if [[ "$line" == *'"method":"initialize"'* ]]; then
            print -r -- '{"id":'${id}',"result":{}}'
          elif [[ "$line" == *'thread/start'* || "$line" == *'thread\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"thread":{"id":"THREAD-DIAG"}}}'
          elif [[ "$line" == *'turn/start'* || "$line" == *'turn\\/start'* ]]; then
            print -r -- '{"id":'${id}',"result":{"turn":{"id":"TURN-DIAG","items":[],"itemsView":"full","status":"inProgress","error":null,"startedAt":0,"completedAt":null,"durationMs":null}}}'
            print -r -- '{"method":"item/agentMessage/delta","params":{"threadId":"THREAD-DIAG","turnId":"TURN-DIAG","itemId":"ITEM-DIAG","delta":"DONE"}}'
            print -r -- '{"method":"item/completed","params":{"threadId":"THREAD-DIAG","turnId":"TURN-DIAG","completedAtMs":0,"item":{"type":"agentMessage","id":"ITEM-DIAG","text":"DONE","phase":null,"memoryCitation":null}}}'
            print -r -- '{"method":"turn/completed","params":{"threadId":"THREAD-DIAG","turn":{"id":"TURN-DIAG","items":[],"itemsView":"full","status":"completed","error":null,"startedAt":0,"completedAt":0,"durationMs":1}}}'
          fi
        done
        """
    )
    defer {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    let conversation = CodexConversation(
        binaryPath: scriptURL.path,
        model: "gpt-5.5",
        effort: "minimal",
        workingDirectory: nil,
        systemPrompt: nil,
        diagnosticsLogURL: diagnosticsURL
    )

    let turn = await conversation.send("diagnose")
    #expect(turn.text == "DONE")

    let deadline = Date().addingTimeInterval(5)
    var logged = ""
    while Date() < deadline {
        logged = (try? String(contentsOf: diagnosticsURL, encoding: .utf8)) ?? ""
        if logged.contains("failed to initialize accessibility session") {
            break
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    #expect(logged.contains("starting codex app-server"))
    #expect(logged.contains("codex app-server stderr"))
    #expect(logged.contains("failed to initialize accessibility session"))
}

@Test func sidekickUserFacingErrorHidesInternalComputerUseFailures() {
    let raw = "The Cua computer-use bridge is not connected in this session, so I can't click and type."
    let friendly = SidekickUserFacingError.replacement(for: raw, isError: false)

    #expect(friendly == "Computer-control error. Details saved in Sidekick Logs.")
    #expect(friendly?.contains("Cua") == false)
    #expect(friendly?.contains("MCP") == false)
    #expect(friendly?.contains("bridge") == false)
    #expect(friendly?.contains("session") == false)
}

@Test func sidekickUserFacingErrorUsesShortCompleteLocalDiagnosticsCopy() {
    #expect(SidekickUserFacingError.replacement(
        for: "unexpected local failure",
        isError: true
    ) == "Local error. Details saved in Sidekick Logs.")
    #expect(SidekickUserFacingError.replacement(
        for: "codex app-server stream failed",
        isError: true
    ) == "Brain error. Details saved in Sidekick Logs.")
    #expect(SidekickUserFacingError.replacement(
        for: "The ChatGPT connection timed out before a final response.",
        isError: true
    ) == "ChatGPT timed out. Try again or switch to Claude.")
    #expect(SidekickUserFacingError.replacement(
        for: "Failed to authenticate. API Error: 401 Invalid authentication credentials",
        isError: true
    ) == "Brain sign-in expired. Sign in again or switch models.")
}

@Test func sidekickUserFacingErrorNamesProviderUsageLimitsDirectly() {
    let raw = "You've hit your monthly spend limit · raise it at claude.ai/settings/usage"
    let friendly = SidekickUserFacingError.replacement(for: raw, isError: false)

    #expect(SidekickUserFacingError.providerLimit(for: raw) == .claude)
    #expect(friendly == "Claude usage limit hit. Raise it at claude.ai/settings/usage.")
    #expect(friendly?.contains("local error") == false)
    #expect(SidekickUserFacingError.providerLimit(for: "OpenAI rate limit exceeded") == .chatGPT)
    #expect(SidekickUserFacingError.providerLimit(for: "xAI insufficient credits") == .xAI)
    #expect(SidekickUserFacingError.providerIssue(for: raw) == .usageLimit(.claude))
    #expect(SidekickUserFacingError.providerIssue(for: "Claude failed to authenticate. API Error: 401 Invalid authentication credentials") == .authentication(.claude))
    #expect(SidekickUserFacingError.providerIssue(for: "The ChatGPT connection timed out before a final response.") == .connection(.chatGPT))
}

@Test func sidekickModelLadderKeepsWakeOptionsAndExecutionSeparate() {
    #expect(SidekickModel.all == [.opus48, .gpt55])

    #expect(SidekickModel.notificationWakeModel(for: .codex) == .gpt54Mini)
    #expect(SidekickModel.recommendationModel(for: .codex) == .gpt54)
    #expect(SidekickModel.notificationWakeModel(for: .claude) == .haiku45)
    #expect(SidekickModel.recommendationModel(for: .claude) == .sonnet46)
    #expect(SidekickModel.all.contains(.gpt54) == false)
    #expect(SidekickModel.all.contains(.gpt54Mini) == false)
    #expect(SidekickModel.all.contains(.haiku45) == false)
    #expect(SidekickModel.all.contains(.sonnet46) == false)
    #expect(SidekickHiddenBrainRouting.backendPreference(
        selectedModel: .gpt55,
        role: .backgroundScreenWake
    ) == [.codex, .claude])
    #expect(SidekickHiddenBrainRouting.backendPreference(
        selectedModel: .gpt55,
        role: .invocationRecommendations
    ) == [.codex, .claude])
    #expect(SidekickHiddenBrainRouting.backendPreference(
        selectedModel: .opus48,
        role: .backgroundScreenWake
    ) == [.claude, .codex])
    #expect(SidekickHiddenBrainRouting.backendPreference(
        selectedModel: .opus48,
        role: .invocationRecommendations
    ) == [.claude, .codex])
}

@Test func backgroundScreenSuggestionsRunOnlyWhileIdle() {
    let idle = SidekickBackgroundScreenSuggestionState(
        enabled: true,
        isTurnRunning: false,
        isVoiceCaptureActive: false,
        isPushToTalkHeld: false,
        isTTSSpeaking: false,
        isPresentingChoices: false,
        isInputMode: false,
        isUserAnnotating: false,
        isAnnotationHoldActive: false,
        isOnboardingActive: false,
        isWorkflowRecording: false,
        hasGuidedTarget: false,
        isSidekickHidden: false
    )

    #expect(SidekickBackgroundScreenSuggestions.shouldRun(state: idle))
    #expect(SidekickBackgroundScreenSuggestions.shouldRun(state: idle.with(isPresentingChoices: true)) == false)
    #expect(SidekickBackgroundScreenSuggestions.shouldRun(state: idle.with(isVoiceCaptureActive: true)) == false)
    #expect(SidekickBackgroundScreenSuggestions.shouldRun(state: idle.with(isPushToTalkHeld: true)) == false)
    #expect(SidekickBackgroundScreenSuggestions.shouldRun(state: idle.with(isTurnRunning: true)) == false)
    #expect(SidekickBackgroundScreenSuggestions.shouldRun(state: idle.with(isInputMode: true)) == false)
    #expect(SidekickBackgroundScreenSuggestions.shouldRun(state: idle.with(isOnboardingActive: true)) == false)
    #expect(SidekickBackgroundScreenSuggestions.shouldRun(state: idle.with(enabled: false)) == false)
}

@Test func backgroundScreenWakeDecisionParsesStructuredOutput() {
    let decision = SidekickBackgroundScreenSuggestions.parseWakeDecision(from: """
    {"shouldShowOptions":true,"reason":"visible failed setup"}
    """)

    #expect(decision == SidekickBackgroundScreenWakeDecision(
        shouldShowOptions: true,
        reason: "visible failed setup"
    ))
    #expect(SidekickBackgroundScreenSuggestions.wakePrompt().contains("every few seconds"))
    #expect(SidekickBackgroundScreenSuggestions.wakeSchema.jsonObject["required"] as? [String] == ["shouldShowOptions", "reason"])
}

@Test func backgroundScreenWakePromptIncludesProactiveFeedback() throws {
    let suiteName = "sidekick-feedback-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SidekickSuggestionFeedbackStore(defaults: defaults)
    let key = SidekickSuggestionFeedbackKey(
        appIdentifier: "com.apple.MobileSMS",
        surface: "focused-draft"
    )
    let now = Date(timeIntervalSince1970: 1_000)

    store.recordImpression(for: key, now: now)
    let summary = store.recordIgnore(for: key, now: now.addingTimeInterval(10))
    let localDecision = SidekickProactiveIntentDecision(
        action: .watchForChange,
        intent: "watch_focused_draft",
        score: 0.78,
        reason: "User is actively composing.",
        overridesFeedbackCooldown: false
    )
    let prompt = SidekickBackgroundScreenSuggestions.wakePrompt(
        feedback: summary,
        localDecision: localDecision,
        now: now.addingTimeInterval(20)
    )

    #expect(prompt.contains("Recent proactive suggestion feedback"))
    #expect(prompt.contains("Local proactive intent ranker"))
    #expect(prompt.contains("watch_focused_draft"))
    #expect(prompt.contains("expected user engagement"))
    #expect(prompt.contains("interruption cost"))
    #expect(prompt.contains("com.apple.MobileSMS|focused-draft"))
    #expect(prompt.contains("shown: 1"))
    #expect(prompt.contains("ignored by auto-hide: 1"))
    #expect(prompt.contains("consecutive ignores: 1"))
    #expect(prompt.contains("negative feedback"))
}

@Test func proactiveSuggestionFeedbackLearnsIgnoreCooldownAndEngagementReset() throws {
    let suiteName = "sidekick-feedback-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SidekickSuggestionFeedbackStore(defaults: defaults)
    let key = SidekickSuggestionFeedbackKey(
        appIdentifier: "com.apple.MobileSMS",
        surface: "focused-draft"
    )
    let now = Date(timeIntervalSince1970: 2_000)

    #expect(store.shouldSuppress(key, now: now) == false)
    store.recordImpression(for: key, now: now)
    let ignored = store.recordIgnore(for: key, now: now.addingTimeInterval(10))

    #expect(ignored.impressions == 1)
    #expect(ignored.ignores == 1)
    #expect(ignored.consecutiveIgnores == 1)
    #expect(store.shouldSuppress(key, now: now.addingTimeInterval(20)))
    #expect(store.shouldSuppress(key, now: now.addingTimeInterval(200)) == false)

    let engaged = store.recordEngagement(for: key, now: now.addingTimeInterval(220))
    #expect(engaged.engagements == 1)
    #expect(engaged.consecutiveIgnores == 0)
    #expect(store.shouldSuppress(key, now: now.addingTimeInterval(221)) == false)
}

@Test func proactiveSuggestionFeedbackGroupsFocusedDraftByAppAndSurface() {
    let context = DesktopContextSnapshot(
        app: .init(name: "Messages", bundleIdentifier: "com.apple.MobileSMS", processIdentifier: 42),
        window: nil,
        screen: nil,
        browser: nil
    )
    let tree = DesktopAccessibilityTreeSnapshot(
        appName: "Messages",
        bundleIdentifier: "com.apple.MobileSMS",
        processIdentifier: 42,
        nodes: [
            .init(
                depth: 0,
                role: "AXWindow",
                subrole: nil,
                roleDescription: "window",
                title: "Messages",
                label: nil,
                value: nil,
                identifier: nil,
                focused: nil,
                frame: nil,
                actions: []
            ),
            .init(
                depth: 1,
                role: "AXTextArea",
                subrole: nil,
                roleDescription: "text area",
                title: nil,
                label: nil,
                value: "This is my draft reply.",
                identifier: "message-composer",
                focused: true,
                frame: nil,
                actions: ["AXConfirm"]
            ),
        ],
        issue: nil
    )

    let key = SidekickSuggestionFeedback.contextKey(
        desktopContext: context,
        accessibilityTree: tree
    )

    #expect(key.appIdentifier == "com.apple.MobileSMS")
    #expect(key.surface == "focused-draft")
}

@Test func proactiveIntentRankerWatchesImportantViewingWithoutInterrupting() {
    let context = DesktopContextSnapshot(
        app: .init(name: "Arc", bundleIdentifier: "company.thebrowser.Browser", processIdentifier: 42),
        window: .init(
            title: "Important launch video - YouTube",
            ownerName: "Arc",
            ownerProcessIdentifier: 42,
            windowIdentifier: 7,
            bounds: CGRect(x: 0, y: 0, width: 1200, height: 800)
        ),
        screen: nil,
        browser: .init(title: "Important launch video - YouTube", url: "https://youtube.com/watch?v=demo")
    )
    let tree = DesktopAccessibilityTreeSnapshot(
        appName: "Arc",
        bundleIdentifier: "company.thebrowser.Browser",
        processIdentifier: 42,
        nodes: [
            .init(
                depth: 0,
                role: "AXWindow",
                subrole: nil,
                roleDescription: "window",
                title: "Important launch video - YouTube",
                label: nil,
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: []
            ),
            .init(
                depth: 1,
                role: "AXButton",
                subrole: nil,
                roleDescription: "button",
                title: "Pause",
                label: nil,
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: ["AXPress"]
            ),
        ],
        issue: nil
    )

    let decision = SidekickProactiveIntentRanker.rank(
        desktopContext: context,
        accessibilityTree: tree
    )

    #expect(decision.action == .watchForChange)
    #expect(decision.intent == "watch_important_viewing")
}

@Test func proactiveIntentRankerKeepsFocusedDraftQuiet() {
    let context = DesktopContextSnapshot(
        app: .init(name: "Messages", bundleIdentifier: "com.apple.MobileSMS", processIdentifier: 42),
        window: nil,
        screen: nil,
        browser: nil
    )
    let tree = DesktopAccessibilityTreeSnapshot(
        appName: "Messages",
        bundleIdentifier: "com.apple.MobileSMS",
        processIdentifier: 42,
        nodes: [
            .init(
                depth: 0,
                role: "AXWindow",
                subrole: nil,
                roleDescription: "window",
                title: "Messages",
                label: nil,
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: []
            ),
            .init(
                depth: 1,
                role: "AXTextArea",
                subrole: nil,
                roleDescription: "text area",
                title: nil,
                label: nil,
                value: "I am still writing the reply and do not need grammar help yet.",
                identifier: "composer",
                focused: true,
                frame: nil,
                actions: ["AXConfirm"]
            ),
        ],
        issue: nil
    )

    let decision = SidekickProactiveIntentRanker.rank(
        desktopContext: context,
        accessibilityTree: tree
    )

    #expect(decision.action == .watchForChange)
    #expect(decision.intent == "watch_focused_draft")
}

@Test func proactiveIntentRankerShowsOptionsForVisibleErrorDespiteCooldown() throws {
    let suiteName = "sidekick-feedback-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SidekickSuggestionFeedbackStore(defaults: defaults)
    let key = SidekickSuggestionFeedbackKey(appIdentifier: "com.apple.systempreferences", surface: "error-state")
    let now = Date(timeIntervalSince1970: 3_000)
    store.recordImpression(for: key, now: now)
    let feedback = store.recordIgnore(for: key, now: now.addingTimeInterval(5))
    let context = DesktopContextSnapshot(
        app: .init(name: "System Settings", bundleIdentifier: "com.apple.systempreferences", processIdentifier: 42),
        window: nil,
        screen: nil,
        browser: nil
    )
    let tree = DesktopAccessibilityTreeSnapshot(
        appName: "System Settings",
        bundleIdentifier: "com.apple.systempreferences",
        processIdentifier: 42,
        nodes: [
            .init(
                depth: 0,
                role: "AXWindow",
                subrole: nil,
                roleDescription: "window",
                title: "Accessibility",
                label: nil,
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: []
            ),
            .init(
                depth: 1,
                role: "AXStaticText",
                subrole: nil,
                roleDescription: "text",
                title: nil,
                label: "Failed to enable Accessibility. Permission denied.",
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: []
            ),
        ],
        issue: nil
    )

    let decision = SidekickProactiveIntentRanker.rank(
        desktopContext: context,
        accessibilityTree: tree,
        feedback: feedback,
        now: now.addingTimeInterval(10)
    )

    #expect(feedback.shouldSuppress(now: now.addingTimeInterval(10)))
    #expect(decision.action == .showOptions)
    #expect(decision.intent == "explain_or_fix_error")
    #expect(decision.overridesFeedbackCooldown)
}

@Test func proactiveIntentRankerAsksWakeModelForAmbiguousDialog() {
    let context = DesktopContextSnapshot(
        app: .init(name: "Installer", bundleIdentifier: "com.apple.installer", processIdentifier: 42),
        window: nil,
        screen: nil,
        browser: nil
    )
    let tree = DesktopAccessibilityTreeSnapshot(
        appName: "Installer",
        bundleIdentifier: "com.apple.installer",
        processIdentifier: 42,
        nodes: [
            .init(
                depth: 0,
                role: "AXWindow",
                subrole: "AXDialog",
                roleDescription: "dialog",
                title: "Installer",
                label: nil,
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: []
            ),
            .init(
                depth: 1,
                role: "AXButton",
                subrole: nil,
                roleDescription: "button",
                title: "Continue",
                label: nil,
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: ["AXPress"]
            ),
            .init(
                depth: 1,
                role: "AXButton",
                subrole: nil,
                roleDescription: "button",
                title: "Cancel",
                label: nil,
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: ["AXPress"]
            ),
        ],
        issue: nil
    )

    let decision = SidekickProactiveIntentRanker.rank(
        desktopContext: context,
        accessibilityTree: tree
    )

    #expect(decision.action == .evaluateWithWakeModel)
    #expect(decision.intent == "help_with_dialog")
}

@Test func proactiveIntentRankerIgnoresBrowserDebuggingInfobarDialog() {
    let context = DesktopContextSnapshot(
        app: .init(name: "Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 42),
        window: .init(
            title: "Companion Library",
            ownerName: "Chrome",
            ownerProcessIdentifier: 42,
            windowIdentifier: 7,
            bounds: CGRect(x: 0, y: 0, width: 1200, height: 800)
        ),
        screen: nil,
        browser: .init(title: "Companion Library", url: "https://companion.ai/library")
    )
    let tree = DesktopAccessibilityTreeSnapshot(
        appName: "Chrome",
        bundleIdentifier: "com.google.Chrome",
        processIdentifier: 42,
        nodes: [
            .init(
                depth: 0,
                role: "AXWindow",
                subrole: nil,
                roleDescription: "window",
                title: "Companion Library",
                label: nil,
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: []
            ),
            .init(
                depth: 1,
                role: "AXGroup",
                subrole: "AXDialog",
                roleDescription: "dialog",
                title: nil,
                label: "Chrome is being controlled by automated test software.",
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: []
            ),
            .init(
                depth: 2,
                role: "AXButton",
                subrole: nil,
                roleDescription: "button",
                title: "Close",
                label: nil,
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: ["AXPress"]
            ),
        ],
        issue: nil
    )

    let decision = SidekickProactiveIntentRanker.rank(
        desktopContext: context,
        accessibilityTree: tree
    )

    #expect(decision.action == .doNothing)
    #expect(decision.intent == "do_nothing")
}

@Test func proactiveIntentRankerLearnsRepeatedIgnoredNotificationFatigue() throws {
    let suiteName = "sidekick-feedback-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = SidekickSuggestionFeedbackStore(defaults: defaults)
    let key = SidekickSuggestionFeedbackKey(appIdentifier: "com.apple.MobileSMS", surface: "general")
    let now = Date(timeIntervalSince1970: 4_000)
    store.recordImpression(for: key, now: now)
    _ = store.recordIgnore(for: key, now: now.addingTimeInterval(5))
    store.recordImpression(for: key, now: now.addingTimeInterval(200))
    let feedback = store.recordIgnore(for: key, now: now.addingTimeInterval(205))
    let context = DesktopContextSnapshot(
        app: .init(name: "Messages", bundleIdentifier: "com.apple.MobileSMS", processIdentifier: 42),
        window: nil,
        screen: nil,
        browser: nil
    )
    let tree = DesktopAccessibilityTreeSnapshot(
        appName: "Messages",
        bundleIdentifier: "com.apple.MobileSMS",
        processIdentifier: 42,
        nodes: [
            .init(
                depth: 0,
                role: "AXWindow",
                subrole: nil,
                roleDescription: "window",
                title: "Messages",
                label: nil,
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: []
            ),
            .init(
                depth: 1,
                role: "AXStaticText",
                subrole: nil,
                roleDescription: "text",
                title: nil,
                label: "Unread message from Sam",
                value: nil,
                identifier: nil,
                focused: false,
                frame: nil,
                actions: []
            ),
        ],
        issue: nil
    )

    let decision = SidekickProactiveIntentRanker.rank(
        desktopContext: context,
        accessibilityTree: tree,
        feedback: feedback,
        now: now.addingTimeInterval(210)
    )

    #expect(feedback.shouldSuppress(now: now.addingTimeInterval(210)))
    #expect(decision.action == .watchForChange)
    #expect(decision.intent == "handle_notification")
}

@Test func brainFallbackPolicyOffersChatGPTForClaudeUsageLimit() {
    let raw = "You've hit your monthly spend limit · raise it at claude.ai/settings/usage"
    let offer = BrainFallbackPolicy.offer(
        afterProviderLimitText: raw,
        attemptedModel: .opus48,
        isChatGPTAvailable: true,
        isClaudeAvailable: true
    )

    #expect(BrainFallbackPolicy.shouldOfferChatGPTSwitch(
        afterProviderLimitText: raw,
        selectedModel: .opus48,
        isChatGPTAvailable: true
    ))
    #expect(BrainFallbackPolicy.shouldOfferChatGPTSwitch(
        afterProviderLimitText: raw,
        selectedModel: .opus48,
        isChatGPTAvailable: false
    ) == false)
    #expect(offer?.prompt == "Claude usage limit hit. Switch to ChatGPT?")
    #expect(offer?.actionTitle == "Switch to ChatGPT")
    #expect(offer?.keepTitle == "Keep Claude")
    #expect(offer?.discardTitle == "Discard")
    #expect(offer?.toModel == .gpt55)
    #expect(offer?.reason == .usageLimit)
    #expect(BrainFallbackPolicy.offer(
        afterProviderLimitText: "OpenAI rate limit exceeded",
        attemptedModel: .gpt55,
        isChatGPTAvailable: true,
        isClaudeAvailable: true
    )?.toModel == .opus48)
    #expect(BrainFallbackPolicy.offer(
        afterProviderLimitText: "OpenAI rate limit exceeded",
        attemptedModel: .gpt55,
        isChatGPTAvailable: true,
        isClaudeAvailable: false
    ) == nil)
}

@Test func brainFallbackPolicyOffersClaudeForChatGPTTimeout() {
    let raw = "The ChatGPT connection timed out before a final response."
    let offer = BrainFallbackPolicy.offer(
        afterProviderIssueText: raw,
        attemptedModel: .gpt55,
        isChatGPTAvailable: true,
        isClaudeAvailable: true
    )

    #expect(offer?.prompt == "ChatGPT timed out. Switch to Claude?")
    #expect(offer?.actionTitle == "Switch to Claude")
    #expect(offer?.keepTitle == "Keep and retry")
    #expect(offer?.discardTitle == "Discard")
    #expect(offer?.toModel == .opus48)
    #expect(offer?.reason == .connection)
    #expect(BrainFallbackPolicy.offer(
        afterProviderIssueText: raw,
        attemptedModel: .gpt55,
        isChatGPTAvailable: true,
        isClaudeAvailable: false
    ) == nil)
}

@Test func brainFallbackPolicyOffersChatGPTForClaudeAuthenticationFailure() {
    let raw = "Claude failed to authenticate. API Error: 401 Invalid authentication credentials"
    let offer = BrainFallbackPolicy.offer(
        afterProviderIssueText: raw,
        attemptedModel: .opus48,
        isChatGPTAvailable: true,
        isClaudeAvailable: true
    )

    #expect(offer?.prompt == "Claude sign-in expired. Switch to ChatGPT?")
    #expect(offer?.actionTitle == "Switch to ChatGPT")
    #expect(offer?.keepTitle == "Keep and retry")
    #expect(offer?.toModel == .gpt55)
    #expect(offer?.reason == .authentication)
}

@Test func backgroundScreenSuggestionsDisableAfterRepeatedWakeFailures() {
    #expect(SidekickBackgroundScreenSuggestions.shouldDisable(afterConsecutiveWakeFailures: 2) == false)
    #expect(SidekickBackgroundScreenSuggestions.shouldDisable(afterConsecutiveWakeFailures: 3))
}

@Test func keyboardShortcutMatcherRequiresExactControlSpace() {
    #expect(KeyboardShortcutMonitor.matches(
        keyCode: 49,
        modifierFlags: [.control],
        requiredKeyCode: 49,
        requiredModifiers: [.control]
    ))
    #expect(KeyboardShortcutMonitor.matches(
        keyCode: 49,
        modifierFlags: [.control, .option],
        requiredKeyCode: 49,
        requiredModifiers: [.control]
    ) == false)
    #expect(KeyboardShortcutMonitor.matches(
        keyCode: 36,
        modifierFlags: [.control],
        requiredKeyCode: 49,
        requiredModifiers: [.control]
    ) == false)
}

@Test func keyboardShortcutActivationDelayRejectsShortPresses() {
    #expect(KeyboardShortcutMonitor.hasMetActivationDelay(start: 30, end: 30.23) == false)
    #expect(KeyboardShortcutMonitor.hasMetActivationDelay(start: 30, end: 30.24))
    #expect(KeyboardShortcutMonitor.hasMetActivationDelay(start: 30, end: 30.35))
}

@Test func modifierHoldMonitorRequiresExactControlOnlyForAnnotationMode() {
    #expect(ModifierHoldMonitor.matches(modifierFlags: [.control], requiredModifiers: [.control]))
    #expect(ModifierHoldMonitor.matches(modifierFlags: [.control, .option], requiredModifiers: [.control]) == false)
    #expect(ModifierHoldMonitor.matches(modifierFlags: [.control, .command], requiredModifiers: [.control]) == false)
}

@Test func modifierHoldMonitorRecognizesInterruptedControlPrefix() {
    #expect(ModifierHoldMonitor.hasRequiredModifiers(modifierFlags: [.control, .option], requiredModifiers: [.control]))
    #expect(ModifierHoldMonitor.isInterruptedByAdditionalModifiers(modifierFlags: [.control, .option], requiredModifiers: [.control]))
    #expect(ModifierHoldMonitor.isInterruptedByAdditionalModifiers(modifierFlags: [.control], requiredModifiers: [.control]) == false)
    #expect(ModifierHoldMonitor.isInterruptedByAdditionalModifiers(modifierFlags: [.option], requiredModifiers: [.control]) == false)
}

@Test func modifierHoldMonitorRecognizesDoubleTapTiming() {
    #expect(ModifierHoldMonitor.isTapDuration(start: 10, end: 10.12, maximum: 0.22))
    #expect(ModifierHoldMonitor.isTapDuration(start: 10, end: 10.4, maximum: 0.22) == false)
    #expect(ModifierHoldMonitor.isDoubleTap(previousTap: 10.12, currentTap: 10.38, maximumInterval: 0.36))
    #expect(ModifierHoldMonitor.isDoubleTap(previousTap: 10.12, currentTap: 10.7, maximumInterval: 0.36) == false)
}

@Test func pushToTalkMonitorRequiresExactControlOptionChord() {
    #expect(PushToTalkMonitor.matches(modifierFlags: [.control, .option], requiredModifiers: [.control, .option]))
    #expect(PushToTalkMonitor.matches(modifierFlags: [.control], requiredModifiers: [.control, .option]) == false)
    #expect(PushToTalkMonitor.matches(modifierFlags: [.control, .option, .shift], requiredModifiers: [.control, .option]) == false)
}

@Test func pushToTalkMonitorActivationDelayRejectsShortPresses() {
    #expect(PushToTalkMonitor.hasMetActivationDelay(start: 20, end: 20.23) == false)
    #expect(PushToTalkMonitor.hasMetActivationDelay(start: 20, end: 20.24))
    #expect(PushToTalkMonitor.hasMetActivationDelay(start: 20, end: 20.35))
}

@Test func focusedExternalInputOnlyStartsFromPlainPrintableKeys() {
    #expect(ExternalInputKeyFilter.accepts(
        keyCode: 0,
        characters: "a",
        modifierFlags: [],
        inputAlreadyOpen: false
    ))
    #expect(ExternalInputKeyFilter.accepts(
        keyCode: 49,
        characters: " ",
        modifierFlags: [],
        inputAlreadyOpen: false
    ) == false)
    #expect(ExternalInputKeyFilter.accepts(
        keyCode: 51,
        characters: nil,
        modifierFlags: [],
        inputAlreadyOpen: false
    ) == false)
    #expect(ExternalInputKeyFilter.accepts(
        keyCode: 51,
        characters: nil,
        modifierFlags: [],
        inputAlreadyOpen: true
    ))
    #expect(ExternalInputKeyFilter.accepts(
        keyCode: 0,
        characters: "a",
        modifierFlags: [.command],
        inputAlreadyOpen: false
    ) == false)
}

@Test func sidekickBubbleAcceptsStandardInputEditingCommands() {
    #expect(SidekickBubbleController.acceptsInputEditingCommand(
        charactersIgnoringModifiers: "a",
        modifierFlags: [.command]
    ))
    #expect(SidekickBubbleController.acceptsInputEditingCommand(
        charactersIgnoringModifiers: "v",
        modifierFlags: [.command]
    ))
    #expect(SidekickBubbleController.acceptsInputEditingCommand(
        charactersIgnoringModifiers: "c",
        modifierFlags: [.command]
    ))
    #expect(SidekickBubbleController.acceptsInputEditingCommand(
        charactersIgnoringModifiers: "x",
        modifierFlags: [.command]
    ))
    #expect(SidekickBubbleController.acceptsInputEditingCommand(
        charactersIgnoringModifiers: "v",
        modifierFlags: [.command, .option]
    ) == false)
}

@Test @MainActor func sidekickBubblePastesAndSelectsInputText() {
    let bubble = SidekickBubbleController()
    defer { bubble.hide() }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString("hello from paste", forType: .string)

    let pasteEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: bubble.window.windowNumber,
        context: nil,
        characters: "v",
        charactersIgnoringModifiers: "v",
        isARepeat: false,
        keyCode: 9
    )
    #expect(bubble.receiveExternalInputKey(pasteEvent!) == true)
    #expect(bubble.debugInputText == "hello from paste")

    let selectAllEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: bubble.window.windowNumber,
        context: nil,
        characters: "a",
        charactersIgnoringModifiers: "a",
        isARepeat: false,
        keyCode: 0
    )
    #expect(bubble.receiveExternalInputKey(selectAllEvent!) == true)
    #expect(bubble.debugSelectedRange == NSRange(location: 0, length: "hello from paste".count))
}

@Test @MainActor func sidekickBubbleDoesNotOpenInputFromTypingWhileChoicesAreVisible() {
    let bubble = SidekickBubbleController()
    defer { bubble.hide() }
    var picked = false
    bubble.showChoices("Pick one.", choices: [
        .init(title: "Do it") { picked = true },
    ])

    #expect(bubble.debugChoiceShortcutLabels == ["1"])

    let letterEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: bubble.window.windowNumber,
        context: nil,
        characters: "a",
        charactersIgnoringModifiers: "a",
        isARepeat: false,
        keyCode: 0
    )
    #expect(bubble.isPresentingChoices)
    #expect(bubble.receiveExternalInputKey(letterEvent!) == false)
    #expect(bubble.isInputMode == false)
    #expect(picked == false)

    let numberEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: bubble.window.windowNumber,
        context: nil,
        characters: "1",
        charactersIgnoringModifiers: "1",
        isARepeat: false,
        keyCode: 18
    )
    #expect(bubble.receiveChoiceKey(numberEvent!) == true)
    #expect(picked)
}

@Test @MainActor func sidekickBubbleShowsChoiceShortcutNumbersThroughNine() {
    let bubble = SidekickBubbleController()
    defer { bubble.hide() }
    let choices = (1...10).map { index in
        SidekickBubbleController.Choice(title: "Option \(index)") {}
    }

    bubble.showChoices("Pick one.", choices: choices)

    #expect(bubble.debugChoiceShortcutLabels == [
        "1", "2", "3", "4", "5", "6", "7", "8", "9", nil,
    ])
}

@Test @MainActor func sidekickBubbleAutoHidesChoicesWhenConfigured() {
    let bubble = SidekickBubbleController()
    defer { bubble.hide() }
    let probe = AutoHideProbe()

    bubble.showChoices("Pick one.", choices: [
        .init(title: "Do it") {},
    ], autoHide: 0.05) {
        probe.didFire = true
    }

    #expect(bubble.isPresentingChoices)
    let deadline = Date().addingTimeInterval(0.5)
    while bubble.isVisible && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    #expect(bubble.isVisible == false)
    #expect(probe.didFire)
}

@Test @MainActor func sidekickBubbleDoesNotOpenInputWhileChoicePromptIsTyping() {
    let bubble = SidekickBubbleController()
    defer { bubble.hide() }
    bubble.showChoicesTyping("Pick one.", choices: [
        .init(title: "Do it") {},
    ])

    let letterEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: bubble.window.windowNumber,
        context: nil,
        characters: "a",
        charactersIgnoringModifiers: "a",
        isARepeat: false,
        keyCode: 0
    )
    #expect(bubble.isPresentingChoices)
    #expect(bubble.receiveExternalInputKey(letterEvent!) == false)
    #expect(bubble.isInputMode == false)
}

@Test @MainActor func sidekickBubbleCanOpenWithPrefilledPrompt() {
    let bubble = SidekickBubbleController()
    defer { bubble.hide() }
    let prompt = "Draft a short note."

    bubble.openInput(prefilledText: prompt)

    #expect(bubble.isInputMode)
    #expect(bubble.debugInputText == prompt)
    #expect(bubble.debugSelectedRange == NSRange(
        location: (prompt as NSString).length,
        length: 0
    ))
}

@Test @MainActor func sidekickBubbleConsumesAnchorClickDismissalOnce() {
    let bubble = SidekickBubbleController()
    defer { bubble.hide() }

    bubble.recordInputDismissedByAnchorClick(now: 10)

    #expect(bubble.consumeRecentInputDismissalByAnchorClick(now: 10.2))
    #expect(bubble.consumeRecentInputDismissalByAnchorClick(now: 10.21) == false)
}

@Test @MainActor func sidekickBubbleIgnoresStaleAnchorClickDismissal() {
    let bubble = SidekickBubbleController()
    defer { bubble.hide() }

    bubble.recordInputDismissedByAnchorClick(now: 10)

    #expect(bubble.consumeRecentInputDismissalByAnchorClick(now: 10.5) == false)
}

@Test @MainActor func sidekickCharacterWindowRoutesFocusedTyping() {
    let rendererView = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
    let controller = SidekickWindowController(rendererView: rendererView, size: CGSize(width: 80, height: 80)) { _ in true }
    var handled = false
    controller.onKeyDown = { event in
        handled = event.characters == "a"
        return handled
    }

    let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: controller.window.windowNumber,
        context: nil,
        characters: "a",
        charactersIgnoringModifiers: "a",
        isARepeat: false,
        keyCode: 0
    )

    #expect(controller.window.canBecomeKey)
    #expect(controller.window.canBecomeMain)
    #expect(controller.window.contentView?.acceptsFirstResponder == true)
    controller.window.keyDown(with: event!)
    #expect(handled)
}

@Test func rasterCharacterPackDecodesClippyAnimations() throws {
    let json = """
    {
      "overlayCount": 1,
      "sounds": ["1", "2"],
      "framesize": [124, 93],
      "animations": {
        "Show": {
          "frames": [
            { "duration": 100, "images": [[0, 0]] }
          ]
        },
        "Thinking": {
          "frames": [
            { "duration": 100, "images": [[124, 0]], "exitBranch": 0 }
          ],
          "useExitBranching": true
        }
      }
    }
    """.data(using: .utf8)!

    let pack = try JSONDecoder().decode(RasterCharacterPack.self, from: json)
    #expect(pack.frameSize == [124, 93])
    #expect(pack.animationNames == ["Show", "Thinking"])
    #expect(pack.animations["Thinking"]?.useExitBranching == true)
}

@Test func toolRegistryIncludesApprovalBoundary() throws {
    let tools = ToolRegistry.recommended
    #expect(tools.contains { $0.name == "observe.screen" && $0.approval == .notRequired })
    #expect(tools.contains { $0.name == "computer.get_window_state" && $0.approval == .notRequired })
    #expect(tools.contains { $0.name == "computer.click_element" && $0.approval == .required })
}

@Test func exportedClippyPackLoadsFromResources() throws {
    let root = clippyResourceRoot()
    let pack = try CharacterResourceLoader.loadRasterPack(from: root)
    let manifest = try CharacterResourceLoader.loadManifest(from: root)
    let descriptor = try CharacterResourceLoader.sidekickPackDescriptor(from: root)

    #expect(pack.frameSize == [124, 93])
    #expect(pack.sounds.count == 15)
    #expect(pack.animations.count == 43)
    #expect(manifest.animationCount == 43)
    #expect(descriptor.id == "clippy")
    #expect(descriptor.displayName == "Clippy")
    #expect(descriptor.defaultAnimationByState[.thinking] == "Thinking")
    #expect(pack.animationNames.contains("Show"))
    #expect(pack.animationNames.contains("Thinking"))
    #expect(pack.animationNames.contains("GestureLeft"))
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "map.png").path))
}

@Test func exportedSidekickPacksLoadFromResources() throws {
    #expect(SidekickSpec.all.map(\.id) == [
        "clippy", "bonzi", "f1", "genie", "genius", "links", "merlin", "peedy", "rocky", "rover",
    ])

    for spec in SidekickSpec.all {
        let root = characterRoot(spec.resourceFolderName)
        let pack = try CharacterResourceLoader.loadRasterPack(from: root)
        let manifest = try CharacterResourceLoader.loadManifest(from: root)
        let descriptor = try CharacterResourceLoader.packDescriptor(from: root, spec: spec)

        #expect(pack.animations.isEmpty == false)
        #expect(pack.frameSize.count == 2)
        #expect(manifest.id == spec.id)
        #expect(manifest.displayName == spec.displayName)
        #expect(descriptor.id == spec.id)
        #expect(descriptor.displayName == spec.displayName)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "map.png").path))
    }
}

@Test func sidekickSpecsUsePackBackedGreetingAnimations() throws {
    for spec in SidekickSpec.all {
        let pack = try CharacterResourceLoader.loadRasterPack(from: characterRoot(spec.resourceFolderName))
        #expect(pack.animations[spec.greetingAnimationName] != nil)
    }
}

@Test @MainActor func sidekickCharactersRenderAnInitialVisibleTexture() throws {
    for spec in SidekickSpec.all {
        let character = try SidekickCharacter(
            packRoot: characterRoot(spec.resourceFolderName),
            spec: spec,
            bodyScale: .default
        )
        defer { character.windowController.hide() }

        #expect(character.renderer.sprite.texture != nil)
        #expect(character.renderer.sprite.size.width > 0)
        #expect(character.renderer.sprite.size.height > 0)
    }
}

@Test @MainActor func sidekickCharacterFallsBackForMissingAnimations() throws {
    let rover = try SidekickCharacter(
        packRoot: characterRoot(SidekickSpec.rover.resourceFolderName),
        spec: .rover,
        bodyScale: .default
    )
    defer { rover.windowController.hide() }

    #expect(rover.canPlay("GestureRight") == false)
    #expect(rover.resolveAnimationName("GestureRight") != "GestureRight")
    #expect(rover.canPlay(rover.resolveAnimationName("GestureRight")))
}

@Test @MainActor func choicesBubbleWrapsLongPromptAboveOptions() {
    let bubble = SidekickBubbleController()
    defer { bubble.hide() }
    bubble.setAnchor(CGRect(x: 500, y: 500, width: 80, height: 80))
    bubble.showChoices(
        "I found a few things that could be useful here, but this header is intentionally long enough that it used to take over the bubble before the options.",
        choices: [
            .init(title: "Read this screen") {},
            .init(title: "Explain the error") {},
            .init(title: "Point at the next step") {},
            .init(title: "Ask something else") {},
        ]
    )

    #expect(bubble.debugMessageLineBreakMode == .byWordWrapping)
    #expect(bubble.debugMessageMaximumNumberOfLines == 0)
    #expect(bubble.window.frame.width <= 380)
    #expect(bubble.window.frame.height > 160)
    #expect(bubble.debugChoiceShortcutLabels == ["1", "2", "3", "4"])
}

@Test @MainActor func sidekickSoundBankLoadsOriginalSoundsUnmutedByDefault() throws {
    let root = clippyResourceRoot()
    let soundBank = try SidekickSoundBank(packRoot: root)

    #expect(soundBank.loadedSoundCount == 15)
    #expect(soundBank.isMuted == false)
}

@Test func sidekickSpecOwnsBubbleCopyAndActivityAnimations() throws {
    let spec = SidekickSpec.current

    #expect(spec.id == "clippy")
    #expect(spec.displayName == "Clippy")
    #expect(spec.askPlaceholder == "Ask Clippy…")
    #expect(spec.chatMenuTitle == "Chat with Clippy…")
    #expect(spec.greetingText == "Need a hand?")
    #expect(!spec.greetingText.contains("Mac"))
    #expect(!spec.greetingText.contains("Double-click"))
    #expect(spec.greetingAnimationName == "Greeting")
    #expect(spec.openInputAnimationName == "GetAttention")
    #expect(spec.replyAnimationName == "Explain")

    let thinking = try #require(spec.animation(for: .thinking))
    #expect(thinking.animationName == "IdleHeadScratch")
    #expect(thinking.repeatsUntilStateChange)

    let notification = try #require(spec.animation(for: .notification))
    #expect(notification.animationName == "Alert")
    #expect(notification.repeatsUntilStateChange == false)

    #expect(spec.animation(for: .idle) == nil)
    #expect(spec.balloon.tailHeight == 17)
    #expect(spec.balloon.cornerRadius == 10)
    #expect(spec.balloon.minWidth == 220)
    #expect(spec.balloon.shadowOffset == .zero)
    #expect(spec.balloon.maxWidth == 285)
    #expect(spec.balloon.messageFontSize == 13)
    #expect(spec.balloon.inputFontSize == 13)
    let balloonLayer = SidekickBalloonStyle.makeShapeLayer(spec: spec.balloon)
    #expect(balloonLayer.allowsEdgeAntialiasing)
    #expect(balloonLayer.lineJoin == .round)
    let fill = try #require(spec.balloon.fillColor.usingColorSpace(.deviceRGB))
    #expect(fill.redComponent > 0.99)
    #expect(fill.greenComponent > 0.99)
    #expect(fill.blueComponent < fill.redComponent)
}

@Test func bubbleAutoHideDurationScalesWithReadingTime() {
    let short = SidekickBubbleController.readingAutoHideDelay(for: "Need a hand?")
    let medium = SidekickBubbleController.readingAutoHideDelay(
        for: Array(repeating: "word", count: 40).joined(separator: " "))
    let veryLong = SidekickBubbleController.readingAutoHideDelay(
        for: Array(repeating: "word", count: 200).joined(separator: " "))

    #expect(short == 3.5)
    #expect(medium > short)
    #expect(medium < veryLong)
    #expect(veryLong == 24.0)
}

@Test func spokenBubbleKeepsAVisibleGraceAfterSpeechEnds() {
    #expect(SidekickBubbleController.spokenAutoHideDelay(visibleFor: 0) == 4.0)
    #expect(SidekickBubbleController.spokenAutoHideDelay(visibleFor: 1.5) == 2.5)
    #expect(SidekickBubbleController.spokenAutoHideDelay(visibleFor: 4.0) == 2.0)
    #expect(SidekickBubbleController.spokenAutoHideDelay(visibleFor: 20.0) == 2.0)
}

@Test func bubbleChoiceKeyboardShortcutsSelectAndActivateChoices() {
    #expect(SidekickChoiceKeyboard.action(
        keyCode: 36,
        charactersIgnoringModifiers: "\r",
        selectedIndex: 1,
        choiceCount: 3
    ) == .activate(1))
    #expect(SidekickChoiceKeyboard.action(
        keyCode: 18,
        charactersIgnoringModifiers: "1",
        selectedIndex: 2,
        choiceCount: 3
    ) == .activate(0))
    #expect(SidekickChoiceKeyboard.action(
        keyCode: 20,
        charactersIgnoringModifiers: "3",
        selectedIndex: 0,
        choiceCount: 3
    ) == .activate(2))
    #expect(SidekickChoiceKeyboard.action(
        keyCode: 125,
        charactersIgnoringModifiers: nil,
        selectedIndex: 2,
        choiceCount: 3
    ) == .select(0))
    #expect(SidekickChoiceKeyboard.action(
        keyCode: 126,
        charactersIgnoringModifiers: nil,
        selectedIndex: nil,
        choiceCount: 3
    ) == .select(2))
    #expect(SidekickChoiceKeyboard.action(
        keyCode: 53,
        charactersIgnoringModifiers: "\u{1B}",
        selectedIndex: 0,
        choiceCount: 3
    ) == .cancel)
}

@Test func doubleClickInvocationPromptAsksBrainForScreenSpecificOptions() {
    let prompt = SidekickInvocationSuggestions.recommendationPrompt()
    #expect(prompt.contains("one short bubble line and exactly 3 useful things"))
    #expect(prompt.contains("exact intention may not be clear"))
    #expect(prompt.contains("current accessibility tree and desktop metadata"))
    #expect(prompt.contains("infer why the user probably invoked Sidekick right now"))
    #expect(prompt.contains("structured recommendation response fields"))
    #expect(prompt.contains("Use the AX tree as the primary signal"))
    #expect(prompt.contains("Do not ask for OCR or a screenshot just to recommend these options"))
    #expect(prompt.contains("Pick options by intent, not by app category"))
    #expect(prompt.contains("on this exact screen"))
    #expect(prompt.contains("Do not include a manual \"something else\" option"))
    #expect(prompt.contains("current screen screenshot") == false)
    #expect(prompt.contains("Return only") == false)
    #expect(prompt.contains("JSON") == false)
    #expect(prompt.contains(#""message""#) == false)
    #expect(prompt.contains(#""options""#) == false)
    #expect(prompt.contains("generic app-name headings"))
    #expect(prompt.contains("What should I do with") == false)
    #expect(prompt.contains("Explain this page") == false)
    #expect(prompt.contains("Explain error") == false)
}

@Test func doubleClickInvocationUsesStructuredSchemaForRecommendations() throws {
    let schema = SidekickInvocationSuggestions.recommendationSchema.jsonObject

    #expect(schema["type"] as? String == "object")
    #expect(schema["additionalProperties"] as? Bool == false)
    #expect(schema["required"] as? [String] == ["message", "options"])

    let properties = try #require(schema["properties"] as? [String: Any])
    let message = try #require(properties["message"] as? [String: Any])
    let options = try #require(properties["options"] as? [String: Any])
    #expect(message["maxLength"] as? Int == 140)
    #expect(options["minItems"] as? Int == 3)
    #expect(options["maxItems"] as? Int == 3)

    let item = try #require(options["items"] as? [String: Any])
    #expect(item["required"] as? [String] == ["title", "prompt"])
    let itemProperties = try #require(item["properties"] as? [String: Any])
    let title = try #require(itemProperties["title"] as? [String: Any])
    #expect(title["maxLength"] as? Int == 24)
}

@Test func doubleClickInvocationParsesBrainRecommendations() {
    let text = """
    {
      "message": "Looks like a form. Want a hand?",
      "options": [
        {
          "title": "Fill this form",
          "prompt": "Use the current screen to help me fill this form. Ask before submitting anything."
        },
        {
          "title": "Check required fields",
          "prompt": "Inspect the visible form and point out any required fields that are still empty."
        },
        {
          "title": "Draft a short answer",
          "prompt": "Use the current screen to draft a concise answer for the selected field."
        }
      ]
    }
    """

    let recommendation = SidekickInvocationSuggestions.parseRecommendation(from: text)

    #expect(recommendation?.message == "Looks like a form. Want a hand?")
    #expect(recommendation?.suggestions.map(\.title) == [
        "Fill this form",
        "Check required fields",
        "Draft a short answer",
    ])
    #expect(recommendation?.suggestions[0].prompt == "Use the current screen to help me fill this form. Ask before submitting anything.")
}

@Test func doubleClickInvocationKeepsManualInputEscapeHatch() {
    #expect(SidekickInvocationSuggestions.manualInputTitle == "Something else")
    #expect(SidekickInvocationSuggestions.recommendationPrompt().contains(#""Something else""#) == false)
}

@Test func attentionAnimationDoesNotUseCongratulateCheckMark() {
    #expect(SidekickSpec.current.animation(for: .attention)?.animationName == "GetAttention")
}

@Test func onboardingControlsDoNotRunScreenOrFilePermissionDemo() {
    let request = SidekickOnboardingDemo.demoRequestText

    #expect(request == "")
    #expect(SidekickOnboardingDemo.guidedIntroText == "")
    #expect(SidekickOnboardingDemo.guidedWorkingText == "")
    #expect(SidekickOnboardingDemo.visibleTaskLine == "")
    #expect(request.contains("[POINT") == false)
    #expect(request.contains("[HIGHLIGHT") == false)
    #expect(request.localizedCaseInsensitiveContains("do not quote") == false)
    #expect(request.localizedCaseInsensitiveContains("avoid private") == false)
    #expect(request.localizedCaseInsensitiveContains("sensitive") == false)
    #expect(request.localizedCaseInsensitiveContains("onboarding demo task") == false)

    #expect(SidekickAgentInstructions.shouldAttachScreenshot(text: request, inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldUseScreenAnnotationTool(text: request, inputMode: .text) == false)
    #expect(SidekickAgentInstructions.shouldUseComputerControl(text: request, inputMode: .text) == false)

    #expect(SidekickOnboardingDemo.controlsText.localizedCaseInsensitiveContains("screen") == false)
    #expect(SidekickOnboardingDemo.controlsText.localizedCaseInsensitiveContains("full disk") == false)
    #expect(SidekickOnboardingDemo.controlsText.localizedCaseInsensitiveContains("click me"))
    #expect(SidekickOnboardingDemo.controlsText.localizedCaseInsensitiveContains("double-click me"))
    #expect(SidekickOnboardingDemo.controlsText.contains("Control+Space"))
    #expect(SidekickOnboardingDemo.controlsText.contains("Control+Shift+Space") == false)
    #expect(SidekickOnboardingDemo.controlsText.contains("Control+Option"))
    #expect(SidekickOnboardingDemo.controlsText.contains("Right-click"))
    #expect(SidekickOnboardingDemo.controlsText.localizedCaseInsensitiveContains("annotation") == false)
    #expect(SidekickOnboardingDemo.controlsText.localizedCaseInsensitiveContains("mark the screen") == false)
}

@Test func onboardingResumePointParsesSavedStepAndFallsBackToWelcome() {
    #expect(SidekickOnboardingResumePoint.defaultsKey == "SidekickOnboardingResumePoint")
    #expect(SidekickOnboardingResumePoint.savedPoint(from: nil) == .welcome)
    #expect(SidekickOnboardingResumePoint.savedPoint(from: "not-a-step") == .welcome)
    #expect(SidekickOnboardingResumePoint.savedPoint(from: "permission") == .controls)
    #expect(SidekickOnboardingResumePoint.savedPoint(from: "permissionWalkthrough") == .controls)
    #expect(SidekickOnboardingResumePoint.savedPoint(from: "screenHelp") == .controls)
    #expect(SidekickOnboardingResumePoint.savedPoint(from: "fileAccess") == .controls)
    #expect(SidekickOnboardingResumePoint.savedPoint(from: "demo") == .controls)
    #expect(SidekickOnboardingResumePoint.savedPoint(from: "demoComposer") == .controls)
    #expect(SidekickOnboardingResumePoint.allCases.contains(.screenHelp))
    #expect(SidekickOnboardingResumePoint.allCases.contains(.fileAccess))
    #expect(SidekickOnboardingResumePoint.allCases.contains(.controls))
}

@Test func annotationPaletteUsesSingleYellowStrokeUnlessBackgroundIsLight() {
    #expect(AnnotationPalette.backingTone(luminance: 0.12, fallbackAppearance: .init(named: .darkAqua)!) == nil)
    #expect(AnnotationPalette.backingTone(luminance: 0.55, fallbackAppearance: .init(named: .darkAqua)!) == nil)
    #expect(AnnotationPalette.backingTone(luminance: 0.82, fallbackAppearance: .init(named: .darkAqua)!) == .dark)
    #expect(AnnotationPalette.backingTone(luminance: nil, fallbackAppearance: .init(named: .darkAqua)!) == nil)
    #expect(AnnotationPalette.backingTone(luminance: nil, fallbackAppearance: .init(named: .aqua)!) == .dark)
}

@Test @MainActor func annotationOverlayTracksDismissibleContent() {
    let overlay = AnnotationOverlayWindow()

    #expect(overlay.hasContent == false)
    overlay.show([.dot(center: CGPoint(x: 40, y: 40), progress: 1)])
    #expect(overlay.hasContent == true)
    overlay.clear()
    #expect(overlay.hasContent == false)

    overlay.showSequence([.ring(center: CGPoint(x: 60, y: 60), radius: 22, kind: .target)])
    #expect(overlay.hasContent == true)
    overlay.clear()
    #expect(overlay.hasContent == false)
}

@Test func sidekickBodyScaleClampsAndStepsInQuarterIncrements() {
    #expect(SidekickBodyScale(0.1).value == SidekickBodyScale.minimum)
    #expect(SidekickBodyScale(9).value == SidekickBodyScale.maximum)
    #expect(SidekickBodyScale.default.adjusted(by: 1).value == 1.25)
    #expect(SidekickBodyScale.default.adjusted(by: -1).value == 0.75)
    #expect(SidekickBodyScale(1.25).rasterScale == 2.5)
    #expect(SidekickBodyScale(1.25).percentTitle == "125%")
}

@Test func sidekickSpriteSheetProducesVisibleRestPoseTexture() throws {
    let root = clippyResourceRoot()
    let sheet = try SidekickSpriteSheet(packRoot: root)
    let frames = try #require(sheet.frames(for: "RestPose"))
    let texture = try #require(frames.textures.first)

    #expect(sheet.frameSize == CGSize(width: 124, height: 93))
    #expect(frames.textures.count == 1)
    #expect(texture.size().width > 0)
    #expect(texture.size().height > 0)
}

@Test func sidekickSpriteSheetFramesReuseCachedTextures() throws {
    let root = clippyResourceRoot()
    let sheet = try SidekickSpriteSheet(packRoot: root)
    let animation = try #require(sheet.pack.animations["RestPose"])
    let frame = try #require(animation.frames.first)
    let cached = try #require(sheet.texture(for: frame))
    let frames = try #require(sheet.frames(for: "RestPose"))
    let first = try #require(frames.textures.first)

    #expect(first === cached)
}

@Test func sidekickSpriteSheetPreloadsAnimationTexturesThroughTheCache() throws {
    let root = clippyResourceRoot()
    let sheet = try SidekickSpriteSheet(packRoot: root)
    let count = sheet.preloadTextures(for: ["Processing", "RestPose"])
    let animation = try #require(sheet.pack.animations["Processing"])
    let frame = try #require(animation.frames.first)
    let cached = try #require(sheet.texture(for: frame))
    let frames = try #require(sheet.frames(for: "Processing"))
    let first = try #require(frames.textures.first)

    #expect(count > 1)
    #expect(first === cached)
}

@Test @MainActor func sidekickAnimatorStopsAfterOneShotAnimationExits() throws {
    let root = clippyResourceRoot()
    let sheet = try SidekickSpriteSheet(packRoot: root)
    let renderer = SpriteKitRasterCharacterRenderer(size: sheet.frameSize)
    let animator = SidekickAnimator(sheet: sheet, renderer: renderer)
    var ended = false

    #expect(animator.play("RestPose") { _, state in
        ended = state == .exited
    })

    #expect(ended)
    #expect(animator.isAnimationRunning == false)
}

@Test @MainActor func sidekickAnimatorKeepsMerlinVisibleAfterBlankTerminatorFrame() throws {
    let root = characterRoot("Merlin")
    let sheet = try SidekickSpriteSheet(packRoot: root)
    let renderer = SpriteKitRasterCharacterRenderer(size: sheet.frameSize)
    let animator = SidekickAnimator(sheet: sheet, renderer: renderer)
    var ended = false

    #expect(animator.play("GetAttention") { _, state in
        ended = state == .exited
    })
    for _ in 0..<20 where ended == false {
        animator.advanceFrameSynchronouslyForTesting()
    }

    #expect(ended)
    #expect(animator.isAnimationRunning == false)
    #expect(renderer.sprite.isHidden == false)
    #expect(renderer.sprite.texture != nil)
}

@Test @MainActor func sidekickWindowMoveReportsFrameChanges() {
    let controller = SidekickWindowController(
        rendererView: NSView(frame: CGRect(origin: .zero, size: CGSize(width: 24, height: 24))),
        size: CGSize(width: 24, height: 24)
    ) { _ in true }
    var reportedFrame: CGRect?
    controller.onFrameChanged = { frame in
        reportedFrame = frame
    }

    controller.move(to: CGPoint(x: 120, y: 140), animated: false)

    #expect(reportedFrame?.origin == CGPoint(x: 120, y: 140))
    #expect(reportedFrame?.size == CGSize(width: 24, height: 24))
}

@Test @MainActor func sidekickWindowCanCarryPermissionBundleDuringCharacterDrag() {
    let controller = SidekickWindowController(
        rendererView: NSView(frame: CGRect(origin: .zero, size: CGSize(width: 24, height: 24))),
        size: CGSize(width: 24, height: 24)
    ) { _ in true }
    let appURL = URL(fileURLWithPath: "/Applications/Sidekick.app", isDirectory: true)

    controller.permissionDragAppURL = appURL

    #expect(controller.permissionDragAppURL == appURL)
    controller.permissionDragAppURL = nil
    #expect(controller.permissionDragAppURL == nil)
}

@Test @MainActor func sidekickWindowSingleClickActivatesAfterDoubleClickWindow() async throws {
    let controller = SidekickWindowController(
        rendererView: NSView(frame: CGRect(origin: .zero, size: CGSize(width: 24, height: 24))),
        size: CGSize(width: 24, height: 24)
    ) { _ in true }
    let contentView = try #require(controller.window.contentView)
    var clicks = 0
    controller.onCharacterClick = {
        clicks += 1
    }

    func sendClick(timestamp: TimeInterval, eventNumber: Int, clickCount: Int) throws {
        let down = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 12, y: 12),
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: controller.window.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: clickCount,
            pressure: 1
        ))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: CGPoint(x: 12, y: 12),
            modifierFlags: [],
            timestamp: timestamp + 0.1,
            windowNumber: controller.window.windowNumber,
            context: nil,
            eventNumber: eventNumber + 1,
            clickCount: clickCount,
            pressure: 0
        ))

        contentView.mouseDown(with: down)
        contentView.mouseUp(with: up)
    }

    try sendClick(timestamp: 1, eventNumber: 1, clickCount: 1)
    #expect(clicks == 0)
    try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.1) * 1_000_000_000))
    #expect(clicks == 1)
}

@Test @MainActor func sidekickWindowDoubleClickOpensInvocationWithoutSingleClick() async throws {
    let controller = SidekickWindowController(
        rendererView: NSView(frame: CGRect(origin: .zero, size: CGSize(width: 24, height: 24))),
        size: CGSize(width: 24, height: 24)
    ) { _ in true }
    let contentView = try #require(controller.window.contentView)
    var clicks = 0
    var doubleClicks = 0
    controller.onCharacterClick = {
        clicks += 1
    }
    controller.onCharacterDoubleClick = {
        doubleClicks += 1
    }

    func sendClick(timestamp: TimeInterval, eventNumber: Int, clickCount: Int) throws {
        let down = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 12, y: 12),
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: controller.window.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: clickCount,
            pressure: 1
        ))
        let up = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: CGPoint(x: 12, y: 12),
            modifierFlags: [],
            timestamp: timestamp + 0.1,
            windowNumber: controller.window.windowNumber,
            context: nil,
            eventNumber: eventNumber + 1,
            clickCount: clickCount,
            pressure: 0
        ))

        contentView.mouseDown(with: down)
        contentView.mouseUp(with: up)
    }

    try sendClick(timestamp: 1, eventNumber: 1, clickCount: 1)
    #expect(clicks == 0)
    #expect(doubleClicks == 0)
    try sendClick(timestamp: 1.2, eventNumber: 3, clickCount: 2)
    #expect(clicks == 0)
    #expect(doubleClicks == 1)
    try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.1) * 1_000_000_000))
    #expect(clicks == 0)
    #expect(doubleClicks == 1)
}

@Test @MainActor func spriteRendererResizeUpdatesViewAndSpriteAnchor() {
    let renderer = SpriteKitRasterCharacterRenderer(size: CGSize(width: 24, height: 24))

    renderer.resize(to: CGSize(width: 48, height: 36))

    #expect(renderer.view.frame.size == CGSize(width: 48, height: 36))
    #expect(renderer.scene.scaleMode == .resizeFill)
    #expect(renderer.sprite.position == CGPoint(x: 24, y: 0))
}

@Test @MainActor func sidekickWindowDisablesCompetingBackgroundDrag() {
    let controller = SidekickWindowController(
        rendererView: NSView(frame: CGRect(origin: .zero, size: CGSize(width: 24, height: 24))),
        size: CGSize(width: 24, height: 24)
    ) { _ in true }

    #expect(controller.window.isMovableByWindowBackground == false)
}

@Test func approvalPolicyProtectsSensitiveTools() throws {
    let policy = ApprovalPolicy()
    let shell = ToolInvocation(name: "shell.exec")
    let screen = ToolInvocation(name: "observe.screen")
    let camera = ToolInvocation(name: "observe.camera")
    let payment = ToolInvocation(name: "payment.submit")

    #expect(policy.decision(for: screen) == .allowed)
    #expect(policy.decision(for: shell) == .requiresApproval(.shell, "shell.exec can run local commands."))
    #expect(policy.decision(for: camera) == .requiresApproval(.privacySensitive, "observe.camera can expose private local context."))
    #expect(policy.decision(for: payment) == .requiresApproval(.externalFacing, "payment.submit can send, publish, purchase, or otherwise affect an outside system."))
}

@Test func toolRouterRequiresApprovalBeforeProtectedExecution() async throws {
    let router = ToolRouter()
    let invocation = ToolInvocation(name: "shell.exec", arguments: ["command": .string("pwd")])

    await router.register(name: "shell.exec", executor: ClosureToolExecutor { invocation in
        ToolResult(
            invocationID: invocation.id,
            toolName: invocation.name,
            status: .succeeded,
            summary: "ran",
            payload: .string("/tmp")
        )
    })

    let first = await router.route(invocation)
    if case let .approvalRequired(request) = first {
        #expect(request.risk == .shell)
        #expect(request.invocation.name == "shell.exec")
    } else {
        Issue.record("Expected approval before shell execution.")
    }

    let second = await router.route(invocation, approved: true)
    if case let .completed(result) = second {
        #expect(result.status == .succeeded)
        #expect(result.payload == .string("/tmp"))
    } else {
        Issue.record("Expected approved shell execution to complete.")
    }
}

@Test func voiceEventsDriveSidekickState() throws {
    var machine = SidekickStateMachine(initialState: .idle)

    #expect(machine.apply(.voice(.wakeAccepted)).state == .listening)
    #expect(machine.apply(.voice(.transcriptInterim("open notes"))).state == .hearing)
    #expect(machine.current.lastMessage == "open notes")
    #expect(machine.apply(.voice(.transcriptFinal("open notes"))).state == .thinking)
    #expect(machine.apply(.voice(.assistantAudioStarted)).state == .speaking)
    #expect(machine.apply(.voice(.assistantAudioFinished)).state == .idle)
}

@Test func runtimeMovesToApprovalStateForProtectedTool() async throws {
    let runtime = SidekickRuntime(initialState: .idle)
    let invocation = ToolInvocation(name: "computer.click_element", arguments: ["window_id": .number(123), "element_index": .number(4)])
    let outcome = await runtime.routeTool(invocation)

    if case let .approvalRequired(request) = outcome {
        #expect(request.risk == .ambiguousTarget)
    } else {
        Issue.record("Expected approval for computer click.")
    }

    let snapshot = await runtime.snapshot
    #expect(snapshot.state == .waitingApproval)
    #expect(snapshot.awaitingApproval?.invocation.name == "computer.click_element")
}

@Test func assistantLoopStopsForApprovalRequest() async throws {
    let router = ToolRouter()
    let client = StaticModelClient(response: AssistantTurnResponse(
        toolCalls: [ToolInvocation(name: "shell.exec", arguments: ["command": .string("pwd")])]
    ))
    let loop = AssistantLoop(modelClient: client, toolRouter: router)
    let result = await loop.run(userText: "run pwd")

    #expect(result.stopReason == .approvalRequired)
    #expect(result.approvalRequest?.risk == .shell)
}

@Test func desktopTaskRequestCarriesVoiceAndResponseMode() throws {
    let screenID = UUID()
    let context = DesktopTaskContext(
        focusedAppBundleID: "com.apple.Safari",
        focusedWindowTitle: "Research",
        screenObservationID: screenID
    )
    let request = DesktopTaskRequest(
        inputMode: .voice,
        rawText: "sidekick summarize this",
        interpretedTask: "Summarize the focused Safari window.",
        context: context,
        preferredResponseMode: .bubble
    )

    #expect(request.inputMode == .voice)
    #expect(request.rawText == "sidekick summarize this")
    #expect(request.interpretedTask == "Summarize the focused Safari window.")
    #expect(request.context.screenObservationID == screenID)
    #expect(request.preferredResponseMode == .bubble)
    #expect(request.requiresApprovalBeforeExternalAction == true)
}

@Test func credentialCatalogRecordsLocalSourcesWithoutValues() throws {
    let catalog = CredentialCatalog()
    let anthropic = try #require(catalog.descriptor(for: .anthropic))
    let openAI = try #require(catalog.descriptor(for: .openAI))
    let deepgram = try #require(catalog.descriptor(for: .deepgram))
    let xai = try #require(catalog.descriptor(for: .xAI))

    #expect(anthropic.environmentVariable == "ANTHROPIC_API_KEY")
    #expect(anthropic.sources.contains {
        $0.kind == .sidekickSecretsJSON &&
            $0.path == CredentialCatalog.sidekickSecretsPath &&
            $0.keyPath == "anthropicAPIKey"
    })
    #expect(anthropic.sources.contains {
        $0.kind == .clippySecretsJSON &&
            $0.path == CredentialCatalog.clippySecretsPath &&
            $0.keyPath == "anthropicAPIKey"
    })
    #expect(anthropic.sources.contains {
        $0.kind == .irisSettingsJSON &&
            $0.path == CredentialCatalog.irisSettingsPath &&
            $0.keyPath == "providerKeys.anthropicApiKey"
    })
    #expect(openAI.environmentVariable == "OPENAI_API_KEY")
    #expect(openAI.sources.contains {
        $0.kind == .environment &&
            $0.keyPath == "OPENAI_API_KEY"
    })
    #expect(openAI.sources.contains {
        $0.kind == .sidekickSecretsJSON &&
            $0.path == CredentialCatalog.sidekickSecretsPath &&
            $0.keyPath == "openAIAPIKey"
    })
    #expect(openAI.sources.contains {
        $0.kind == .clippySecretsJSON &&
            $0.path == CredentialCatalog.clippySecretsPath &&
            $0.keyPath == "openAIAPIKey"
    })
    #expect(deepgram.sources.contains {
        $0.kind == .irisSettingsJSON &&
            $0.path == CredentialCatalog.irisSettingsPath &&
            $0.keyPath == "providerKeys.deepgramApiKey"
    })
    #expect(deepgram.sources.contains {
        $0.kind == .nativePreferences &&
            $0.path == CredentialCatalog.irisNativePreferencesPath &&
            $0.keyPath == "providerKeys.deepgram-api-key"
    })
    #expect(xai.environmentVariable == "XAI_API_KEY")
    #expect(xai.sources.contains {
        $0.kind == .irisSettingsJSON &&
            $0.path == CredentialCatalog.irisSettingsPath &&
            $0.keyPath == "providerKeys.xaiApiKey"
    })
    #expect(xai.sources.contains {
        $0.kind == .nativePreferences &&
            $0.path == CredentialCatalog.irisNativePreferencesPath &&
            $0.keyPath == "providerKeys.xai-api-key"
    })
    #expect(CredentialCatalog.sidekickSecretsPath.hasSuffix("/Library/Application Support/Sidekick/Secrets.json"))
    #expect(CredentialCatalog.clippySecretsPath.hasSuffix("/Library/Application Support/Clippy/Secrets.json"))
    #expect(CredentialCatalog.irisSettingsPath.hasSuffix("/Library/Application Support/Iris/settings.json"))
    #expect(CredentialCatalog.irisNativePreferencesPath.hasSuffix("/Library/Preferences/ai.companion.iris.mac.plist"))
}

@Test func localBrainAPIKeysAreInjectedFromSidekickClippyAndIrisStores() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretsURL = directory.appendingPathComponent("Secrets.json")
    let legacySecretsURL = directory.appendingPathComponent("LegacySecrets.json")
    let irisURL = directory.appendingPathComponent("settings.json")
    try """
    {
      "anthropicAPIKey": "anthropic-from-sidekick",
      "openAIAPIKey": ""
    }
    """.write(to: secretsURL, atomically: true, encoding: .utf8)
    try """
    {
      "openAIAPIKey": "openai-from-clippy"
    }
    """.write(to: legacySecretsURL, atomically: true, encoding: .utf8)
    try """
    {
      "providerKeys": {
        "openaiApiKey": "openai-from-iris"
      }
    }
    """.write(to: irisURL, atomically: true, encoding: .utf8)

    let environment = SidekickSecrets.environmentByAddingLocalAPIKeys(
        to: [
            "ANTHROPIC_API_KEY": "",
        ],
        secretsFileURL: secretsURL,
        legacySecretsFileURL: legacySecretsURL,
        irisSettingsURL: irisURL,
        nativePreferenceReader: { _ in nil }
    )

    #expect(environment["ANTHROPIC_API_KEY"] == "anthropic-from-sidekick")
    #expect(environment["OPENAI_API_KEY"] == "openai-from-clippy")
}

@Test func voiceSidecarReportsOnlyPresenceForEnvironment() throws {
    let config = VoiceSidecarConfiguration.irisVoiceSidecar
    let status = config.environmentStatus(from: [
        "DEEPGRAM_API_KEY": "dg-key",
        "OPENAI_API_KEY": "",
    ])

    #expect(config.wakeWord == "clippy")
    #expect(config.port == 4748)
    #expect(config.executablePath == "uv")
    #expect(config.workingDirectoryPath.hasSuffix("/Library/Application Support/Sidekick/VoiceSidecar/iris-voice"))
    #expect(status["DEEPGRAM_API_KEY"] == "present")
    #expect(status["OPENAI_API_KEY"] == "missing")
    #expect(status["ANTHROPIC_API_KEY"] == "missing")
}

@Test func wakeWordDetectorAcceptsOnlyConfiguredPhraseAboveThreshold() {
    let detector = WakeWordDetector(acceptedLabels: ["hey_clippy"], threshold: 0.8)

    #expect(detector.detection(label: "hey clippy", confidence: 0.81) == WakeWordDetection(label: "hey clippy", confidence: 0.81))
    #expect(detector.detection(label: "Hey-Clippy", confidence: 0.81) == WakeWordDetection(label: "Hey-Clippy", confidence: 0.81))
    #expect(detector.detection(label: "hey_clippy", confidence: 0.79) == nil)
    #expect(detector.detection(label: "not_wake", confidence: 0.99) == nil)
}

@Test func wakeWordDetectorRequiresWakeWordToBeTopClassification() {
    let detector = WakeWordDetector(acceptedLabels: ["hey_clippy"], threshold: 0.8)

    #expect(detector.detection(rankedClassifications: [
        (label: "not_wake", confidence: 0.99),
        (label: "hey_clippy", confidence: 0.98),
    ]) == nil)
    #expect(detector.detection(rankedClassifications: [
        (label: "hey_clippy", confidence: 0.81),
        (label: "not_wake", confidence: 0.19),
    ]) == WakeWordDetection(label: "hey_clippy", confidence: 0.81))
}

@Test func wakePhraseVerifierMatchesOnlyExplicitPhrase() {
    let verifier = WakePhraseVerifier()

    #expect(verifier.containsWakePhrase("Hey, Clippy, can you hear me?"))
    #expect(verifier.containsWakePhrase("hay clippy"))
    #expect(verifier.containsWakePhrase("hey clipy open this"))
    #expect(verifier.containsWakePhrase("sidekick can you hear me") == false)
    #expect(verifier.containsWakePhrase("this clip is weird") == false)
}

@Test func wakeWordModelLocatorUsesExistingExplicitModelPath() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let modelURL = directory.appendingPathComponent("CustomHeyClippy.mlmodel")
    try Data("model".utf8).write(to: modelURL)

    let located = WakeWordModelLocator.defaultModelURL(
        environment: [WakeWordModelLocator.environmentKey: modelURL.path],
        bundle: .main
    )

    #expect(located == modelURL)
}

@Test func voiceActivityDetectorIgnoresQuietAudio() {
    var detector = VoiceActivityDetector(configuration: .init(
        speechStartThresholdDBFS: -35,
        speechEndThresholdDBFS: -45,
        minimumSpeechDuration: 0.05,
        minimumSilenceDuration: 0.05
    ))

    let quiet = pcm16Constant(amplitude: 8, sampleCount: 1_600)

    #expect(detector.process(pcm16Data: quiet) == nil)
    #expect(detector.isSpeechActive == false)
}

@Test func voiceActivityDetectorStartsAndStopsWithHysteresis() {
    var detector = VoiceActivityDetector(configuration: .init(
        speechStartThresholdDBFS: -35,
        speechEndThresholdDBFS: -45,
        minimumSpeechDuration: 0.10,
        minimumSilenceDuration: 0.20
    ))

    let speech = pcm16Constant(amplitude: 8_000, sampleCount: 800)
    let silence = pcm16Constant(amplitude: 0, sampleCount: 1_600)

    #expect(detector.process(pcm16Data: speech) == nil)
    #expect(detector.process(pcm16Data: speech) == VoiceActivityEvent(
        isSpeechActive: true,
        levelDBFS: detector.lastLevelDBFS
    ))
    #expect(detector.isSpeechActive)

    #expect(detector.process(pcm16Data: silence) == nil)
    #expect(detector.process(pcm16Data: silence) == VoiceActivityEvent(
        isSpeechActive: false,
        levelDBFS: -Double.infinity
    ))
    #expect(detector.isSpeechActive == false)
}

@Test func microphoneTapCoordinatorRejectsConcurrentOwners() throws {
    let coordinator = MicrophoneTapCoordinator()

    try coordinator.acquire(.wakeWord)
    defer { coordinator.release(.wakeWord) }

    do {
        try coordinator.acquire(.deepgramSTT)
        Issue.record("Expected second microphone tap owner to be rejected.")
    } catch MicrophoneTapCoordinatorError.alreadyOwned(let owner) {
        #expect(owner == .wakeWord)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func voiceCaptureAudioWrapsPCM16AsWAV() throws {
    let pcm = Data([0x01, 0x00, 0xff, 0x7f])
    let audio = VoiceCaptureAudio(pcm16Data: pcm, sampleRate: 16_000, channels: 1)
    let wav = audio.wavData()

    #expect(audio.durationSeconds == 0.000125)
    #expect(String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
    #expect(String(data: wav.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE")
    #expect(String(data: wav.dropFirst(12).prefix(4), encoding: .ascii) == "fmt ")
    #expect(String(data: wav.dropFirst(36).prefix(4), encoding: .ascii) == "data")
    #expect(wav.suffix(4) == pcm)
}

@Test func speakerIdentityProfileStoreRoundTripsLocally() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("VoiceProfile.json")
    let profile = SpeakerIdentityProfile(userId: "owner", displayName: "Owner", embedding: [0.1, 0.2, 0.3])

    try SpeakerIdentityProfileStore.save(profile, to: url)
    #expect(SpeakerIdentityProfileStore.load(from: url) == profile)

    try SpeakerIdentityProfileStore.delete(from: url)
    #expect(SpeakerIdentityProfileStore.load(from: url) == nil)
}

@Test func xaiTTSConvertsSplitLinear16FramesToFloatPCM() throws {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    var carry = Data([0x00])

    let buffer = try #require(XAITTS.makePCMBuffer(
        fromLinear16: Data([0x80, 0xff, 0x7f, 0x00]),
        carry: &carry,
        format: format,
        gain: 1
    ))

    #expect(buffer.frameLength == 2)
    let channel = try #require(buffer.floatChannelData?[0])
    #expect(channel[0] == -1)
    #expect(channel[1] > 0.99)
    #expect(carry == Data([0x00]))
}

@Test func xaiSpeechTagsAreRemovedFromDisplayText() {
    let text = "[chuckle] <whisper>that worked</whisper> [pause]"
    #expect(VoiceSpeechTags.strip(text) == "that worked")
    #expect(VoiceSpeechTags.stripForStreaming("Ready [chuc") == "Ready")
    #expect(VoiceSpeechTags.stripForStreaming("<laugh-spe") == "")
    #expect(VoiceSpeechTags.stripForStreaming("<laugh-speak>That worked</laugh-spe") == "That worked")
    #expect(VoiceSpeechTags.stripForStreaming("array[0") == "array[0")
    #expect(VoiceSpeechTags.instruction.contains("[chuckle]"))
    #expect(VoiceSpeechTags.instruction.contains("<whisper>"))
    #expect(VoiceSpeechTags.instruction.contains("avoid deep"))
}

@Test func sidekickVoiceCatalogUsesOnlyLiveXAIWomanAndManVoices() {
    #expect(SidekickVoice.default.id == "ara")
    #expect(SidekickVoice.all.map(\.id) == ["ara", "rex"])
    #expect(SidekickVoice.ara.displayName == "Ara")
    #expect(SidekickVoice.ara.detail == "Female · Bright")
    #expect(SidekickVoice.rex.displayName == "Rex")
    #expect(SidekickVoice.rex.detail == "Male · Calm")
    #expect(SidekickVoice.by(id: "eve") == nil)
    #expect(SidekickVoice.by(id: "leo") == nil)
    #expect(SidekickVoice.by(id: "grace") == nil)
    #expect(SidekickVoice.by(id: "daniel") == nil)
}

@Test func xaiTTSRejectsJSONErrorBodiesAsAudio() throws {
    let error = try JSONSerialization.data(withJSONObject: ["error": "Voice not found"])

    #expect(XAITTS.audioBytes(from: error) == nil)
    #expect(XAITTS.errorMessage(from: error) == "Voice not found")
}

@Test func computerUseRoutePolicyRequiresFreshWindowSnapshot() async throws {
    let policy = ComputerUseRoutePolicy()
    let staleAction = ComputerUseElementAction(
        kind: .clickElement,
        pid: 100,
        windowID: 200,
        elementIndex: 3,
        snapshotID: UUID()
    )
    let staleDecision = await policy.decision(for: staleAction)
    #expect(staleDecision == .blocked("Computer action requires a fresh getWindowState snapshot for the same pid and windowID."))

    let snapshot = ComputerUseWindowState(pid: 100, windowID: 200, elementCount: 8)
    await policy.recordSnapshot(snapshot)
    let freshAction = ComputerUseElementAction(
        kind: .clickElement,
        pid: 100,
        windowID: 200,
        elementIndex: 3,
        snapshotID: snapshot.id
    )
    let freshDecision = await policy.decision(for: freshAction)
    #expect(freshDecision == .allowed)
}

@Test func computerUseRoutePolicyRequiresElementIndexForElementActions() async throws {
    let policy = ComputerUseRoutePolicy()
    let snapshot = ComputerUseWindowState(pid: 100, windowID: 200, elementCount: 8)
    await policy.recordSnapshot(snapshot)

    let missingTarget = ComputerUseElementAction(
        kind: .clickElement,
        pid: 100,
        windowID: 200,
        snapshotID: snapshot.id
    )
    let decision = await policy.decision(for: missingTarget)
    #expect(decision == .blocked("Element-indexed computer action requires elementIndex from getWindowState."))
}

private func clippyResourceRoot() -> URL {
    characterRoot("Clippy")
}

private func characterRoot(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Resources/Characters/\(name)")
}

private struct StaticModelClient: AssistantModelClient {
    let response: AssistantTurnResponse

    func nextTurn(_ request: AssistantTurnRequest) async throws -> AssistantTurnResponse {
        response
    }
}
