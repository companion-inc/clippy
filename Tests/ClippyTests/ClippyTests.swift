import AppKit
import AVFoundation
import Foundation
import Testing
@testable import ClippyCore

private func writeExecutableScript(named name: String, contents: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

@Test func actionQueueRunsFifoAndInterrupts() async throws {
    let queue = MascotActionQueue()
    let first = MascotAction(command: .setState(.thinking))
    let second = MascotAction(command: .setState(.done))

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

@Test func codexConversationResumesTheSameThreadAcrossTurns() async throws {
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-codex-log-\(UUID().uuidString).txt")
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
        systemPrompt: nil
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
        systemPrompt: nil
    )

    var iterator = conversation.stream("stream me").makeAsyncIterator()
    let first = await iterator.next()

    guard case .partial("EARLY ") = first else {
        Issue.record("Expected Codex app-server agentMessage delta to arrive before the completed item.")
        return
    }
}

@Test func codexConversationStreamCancellationTerminatesTheChildProcess() async throws {
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-codex-cancel-\(UUID().uuidString).txt")
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
        systemPrompt: nil
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
    let descriptor = try CharacterResourceLoader.clippyPackDescriptor(from: root)

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

@Test func clippyThemeOwnsBubbleCopyAndActivityAnimations() throws {
    let theme = MascotTheme.clippy

    #expect(theme.id == "clippy")
    #expect(theme.displayName == "Clippy")
    #expect(theme.askPlaceholder == "Ask Clippy…")
    #expect(theme.chatMenuTitle == "Chat with Clippy…")
    #expect(theme.greetingAnimationName == "Greeting")
    #expect(theme.openInputAnimationName == "GetAttention")
    #expect(theme.replyAnimationName == "Explain")

    let thinking = try #require(theme.animation(for: .thinking))
    #expect(thinking.animationName == "IdleHeadScratch")
    #expect(thinking.repeatsUntilStateChange)

    let notification = try #require(theme.animation(for: .notification))
    #expect(notification.animationName == "Alert")
    #expect(notification.repeatsUntilStateChange == false)

    #expect(theme.animation(for: .idle) == nil)
    #expect(theme.balloon.tailHeight == 14)
    let fill = try #require(theme.balloon.fillColor.usingColorSpace(.deviceRGB))
    #expect(fill.redComponent > 0.99)
    #expect(fill.greenComponent > 0.99)
    #expect(fill.blueComponent < fill.redComponent)
}

@Test func clippySpriteSheetProducesVisibleRestPoseTexture() throws {
    let root = clippyResourceRoot()
    let sheet = try ClippySpriteSheet(packRoot: root)
    let frames = try #require(sheet.frames(for: "RestPose"))
    let texture = try #require(frames.textures.first)

    #expect(sheet.frameSize == CGSize(width: 124, height: 93))
    #expect(frames.textures.count == 1)
    #expect(texture.size().width > 0)
    #expect(texture.size().height > 0)
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

@Test func voiceEventsDriveMascotState() throws {
    var machine = MascotStateMachine(initialState: .idle)

    #expect(machine.apply(.voice(.wakeAccepted)).state == .listening)
    #expect(machine.apply(.voice(.transcriptInterim("open notes"))).state == .hearing)
    #expect(machine.current.lastMessage == "open notes")
    #expect(machine.apply(.voice(.transcriptFinal("open notes"))).state == .thinking)
    #expect(machine.apply(.voice(.assistantAudioStarted)).state == .speaking)
    #expect(machine.apply(.voice(.assistantAudioFinished)).state == .idle)
}

@Test func runtimeMovesToApprovalStateForProtectedTool() async throws {
    let runtime = ClippyRuntime(initialState: .idle)
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
        rawText: "clippy summarize this",
        interpretedTask: "Summarize the focused Safari window.",
        context: context,
        preferredResponseMode: .bubble
    )

    #expect(request.inputMode == .voice)
    #expect(request.rawText == "clippy summarize this")
    #expect(request.interpretedTask == "Summarize the focused Safari window.")
    #expect(request.context.screenObservationID == screenID)
    #expect(request.preferredResponseMode == .bubble)
    #expect(request.requiresApprovalBeforeExternalAction == true)
}

@Test func credentialCatalogRecordsLocalSourcesWithoutValues() throws {
    let catalog = CredentialCatalog()
    let openAI = try #require(catalog.descriptor(for: .openAI))
    let deepgram = try #require(catalog.descriptor(for: .deepgram))

    #expect(openAI.environmentVariable == "OPENAI_API_KEY")
    #expect(openAI.sources.contains {
        $0.kind == .environment &&
            $0.keyPath == "OPENAI_API_KEY"
    })
    #expect(deepgram.sources.contains {
        $0.kind == .irisSettingsJSON &&
            $0.path == CredentialCatalog.irisSettingsPath &&
            $0.keyPath == "providerKeys.deepgramApiKey"
    })
}

@Test func voiceSidecarReportsOnlyPresenceForEnvironment() throws {
    let config = VoiceSidecarConfiguration.irisVoiceSidecar
    let status = config.environmentStatus(from: [
        "DEEPGRAM_API_KEY": "dg-key",
        "OPENAI_API_KEY": "",
    ])

    #expect(config.wakeWord == "clippy")
    #expect(config.port == 4748)
    #expect(status["DEEPGRAM_API_KEY"] == "present")
    #expect(status["OPENAI_API_KEY"] == "missing")
    #expect(status["ANTHROPIC_API_KEY"] == "missing")
}

@Test func deepgramTTSConvertsSplitLinear16FramesToFloatPCM() throws {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    var carry = Data([0x00])

    let buffer = try #require(DeepgramTTS.makePCMBuffer(
        fromLinear16: Data([0x80, 0xff, 0x7f, 0x00]),
        carry: &carry,
        format: format
    ))

    #expect(buffer.frameLength == 2)
    let channel = try #require(buffer.floatChannelData?[0])
    #expect(channel[0] == -1)
    #expect(channel[1] > 0.99)
    #expect(carry == Data([0x00]))
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
