import AppKit
import Foundation
import Testing
@testable import SidekickCore

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

@Test func rasterCharacterPackDecodesClippyShape() throws {
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
    #expect(tools.contains { $0.name == "character.morph" && $0.approval == .notRequired })
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
    #expect(thinking.animationName == "Thinking")
    #expect(thinking.repeatsUntilStateChange)

    let notification = try #require(theme.animation(for: .notification))
    #expect(notification.animationName == "Alert")
    #expect(notification.repeatsUntilStateChange == false)

    #expect(theme.animation(for: .idle) == nil)
    #expect(theme.balloon.tailHeight == 12)
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
        $0.kind == .clippyAuthJSON &&
            $0.path == CredentialCatalog.clippyAuthPath &&
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

@Test func claudeCodeEventsMapToClippyStates() throws {
    #expect(AgentStateMapper.state(for: .userPromptSubmit, agentID: .claudeCode) == .thinking)
    #expect(AgentStateMapper.state(for: .preToolUse, agentID: .claudeCode) == .working)
    #expect(AgentStateMapper.state(for: .subagentStart, agentID: .claudeCode) == .juggling)
    #expect(AgentStateMapper.state(for: .permissionRequest, agentID: .claudeCode) == .notification)
    #expect(AgentStateMapper.state(for: .preCompact, agentID: .claudeCode) == .sweeping)
    #expect(AgentStateMapper.state(for: .worktreeCreate, agentID: .claudeCode) == .carrying)
    #expect(AgentStateMapper.state(for: .postToolUseFailure, agentID: .claudeCode) == .error)
    #expect(AgentStateMapper.state(for: .stop, agentID: .claudeCode) == .attention)
}

@Test func codexEventsMapOfficialHooksAndJsonlFallbacks() throws {
    #expect(AgentStateMapper.state(for: .sessionStart, agentID: .codex) == .idle)
    #expect(AgentStateMapper.state(for: .userPromptSubmit, agentID: .codex) == .thinking)
    #expect(AgentStateMapper.state(for: .codexTaskStarted, agentID: .codex) == .thinking)
    #expect(AgentStateMapper.state(for: .codexFunctionCall, agentID: .codex) == .working)
    #expect(AgentStateMapper.state(for: .codexWebSearchCall, agentID: .codex) == .working)
    #expect(AgentStateMapper.state(for: .permissionRequest, agentID: .codex) == .notification)
    #expect(AgentStateMapper.state(for: .codexContextCompacted, agentID: .codex) == .sweeping)
    #expect(AgentStateMapper.state(for: .codexTaskComplete, agentID: .codex, turnUsedTools: false) == .idle)
    #expect(AgentStateMapper.state(for: .codexTaskComplete, agentID: .codex, turnUsedTools: true) == .attention)
}

@Test func agentSessionStoreResolvesHighestPriorityVisibleState() throws {
    var store = AgentSessionStore()
    store.apply(AgentActivityEvent(agentID: .claudeCode, sessionID: "a", lifecycleEvent: .userPromptSubmit))
    #expect(store.visibleState == .thinking)

    store.apply(AgentActivityEvent(agentID: .codex, sessionID: "b", lifecycleEvent: .codexFunctionCall))
    #expect(store.visibleState == .working)

    store.apply(AgentActivityEvent(agentID: .claudeCode, sessionID: "a", lifecycleEvent: .permissionRequest))
    #expect(store.visibleState == .notification)

    store.apply(AgentActivityEvent(agentID: .codex, sessionID: "b", lifecycleEvent: .postToolUseFailure))
    #expect(store.visibleState == .error)
}

@Test func codexCompletionOnlyCelebratesAfterToolUse() throws {
    var store = AgentSessionStore()
    store.apply(AgentActivityEvent(agentID: .codex, sessionID: "turn", lifecycleEvent: .codexUserMessage))
    #expect(store.visibleState == .thinking)

    store.apply(AgentActivityEvent(agentID: .codex, sessionID: "turn", lifecycleEvent: .codexTaskComplete))
    #expect(store.visibleState == .idle)

    store.apply(AgentActivityEvent(agentID: .codex, sessionID: "turn", lifecycleEvent: .codexUserMessage))
    store.apply(AgentActivityEvent(agentID: .codex, sessionID: "turn", lifecycleEvent: .codexFunctionCall))
    store.apply(AgentActivityEvent(agentID: .codex, sessionID: "turn", lifecycleEvent: .codexTaskComplete))
    #expect(store.visibleState == .attention)
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
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Resources/Characters/Clippy")
}

private struct StaticModelClient: AssistantModelClient {
    let response: AssistantTurnResponse

    func nextTurn(_ request: AssistantTurnRequest) async throws -> AssistantTurnResponse {
        response
    }
}
