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
    let queue = ClippyActionQueue()
    let first = ClippyAction(command: .setState(.thinking))
    let second = ClippyAction(command: .setState(.done))

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

@Test func voiceContextNoteReflectsSpokenInputAndSpokenOutput() {
    // Plain typed, bubble-only turn — no voice note at all.
    #expect(ClippyAgentInstructions.voiceContextNote(inputMode: .text, speaking: false) == nil)

    // Typed but replies are spoken — only the write-for-the-ear half.
    let spokenOut = ClippyAgentInstructions.voiceContextNote(inputMode: .text, speaking: true)
    #expect(spokenOut != nil)
    #expect(spokenOut?.contains("read aloud") == true)
    #expect(spokenOut?.contains("Clippy voice") == true)
    #expect(spokenOut?.contains("SPOKE this") == false)

    // Spoken input, silent replies — only the read-past-transcription-typos half.
    let spokenIn = ClippyAgentInstructions.voiceContextNote(inputMode: .voice, speaking: false)
    #expect(spokenIn != nil)
    #expect(spokenIn?.contains("SPOKE this") == true)
    #expect(spokenIn?.contains("transcribed") == true)
    #expect(spokenIn?.contains("read aloud") == false)

    // Full voice turn — both halves present.
    let both = ClippyAgentInstructions.voiceContextNote(inputMode: .voice, speaking: true)
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

@Test func brainMessageOrdersDesktopContextScreenshotVoiceThenText() throws {
    let context = DesktopContextSnapshot(
        app: .init(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 123),
        window: nil,
        screen: nil,
        browser: nil
    )
    let msg = ClippyAgentInstructions.brainMessage(
        text: "whats on my screen",
        screenshotPath: "/tmp/shot.png",
        screenshotPixelWidth: 3456,
        screenshotPixelHeight: 2234,
        inputMode: .voice,
        speaking: true,
        desktopContext: context)
    // Desktop context first, screenshot second, voice note third, user's words last.
    let contextIdx = try #require(msg.range(of: "Current desktop context")?.lowerBound)
    let shotIdx = try #require(msg.range(of: "Current full-display screenshot")?.lowerBound)
    let voiceIdx = try #require(msg.range(of: "Voice mode")?.lowerBound)
    let textIdx = try #require(msg.range(of: "whats on my screen")?.lowerBound)
    #expect(contextIdx < shotIdx)
    #expect(shotIdx < voiceIdx)
    #expect(voiceIdx < textIdx)
    #expect(msg.contains("3456x2234 px"))
    #expect(msg.contains("active app: Google Chrome"))

    // A typed, silent turn carries desktop metadata + text but no voice note.
    let quiet = ClippyAgentInstructions.brainMessage(
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

    let guided = ClippyAgentInstructions.brainMessage(
        text: "draw on this",
        screenshotPath: "/tmp/shot.png",
        screenshotPixelWidth: 1600,
        screenshotPixelHeight: 1034,
        inputMode: .text,
        speaking: false,
        desktopContext: context,
        requiresVisualGrounding: true)
    #expect(guided.contains("Clippy-style guided visual turn"))
    #expect(guided.contains("Do not answer text-only"))
    #expect(guided.contains("[TARGET]"))
    #expect(guided.contains("[HOVER]"))
    #expect(guided.contains("construction beats"))
    #expect(guided.contains("drawn in order"))
    #expect(guided.contains("missing construction"))
    #expect(guided.contains("[SHAPE:polygon:...] beats for regions/areas"))
    #expect(guided.contains("Do not merely underline existing labels"))
    #expect(guided.contains("[TARGET:x,y,r:label]"))
    #expect(guided.contains("subject-specific template"))
    #expect(guided.contains("Pythagorean") == false)
}

@Test func visualGroundingRepairMessageIsGenericAndScreenshotGrounded() {
    let context = DesktopContextSnapshot(
        app: .init(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 123),
        window: nil,
        screen: nil,
        browser: .init(title: "Demo", url: "http://127.0.0.1/demo")
    )
    let msg = ClippyAgentInstructions.visualGroundingRepairMessage(
        originalUserText: "draw on this",
        previousAssistantText: "Here is a text-only explanation.",
        screenshotPath: "/tmp/shot.png",
        screenshotPixelWidth: 1600,
        screenshotPixelHeight: 1034,
        desktopContext: context
    )
    #expect(msg.contains("Visual grounding repair"))
    #expect(msg.contains("had no renderable grounding tags"))
    #expect(msg.contains("/tmp/shot.png (1600x1034 px)"))
    #expect(msg.contains("[POINT]"))
    #expect(msg.contains("[TARGET]"))
    #expect(msg.contains("[HOVER]"))
    #expect(msg.contains("[HIGHLIGHT]"))
    #expect(msg.contains("[SHAPE]"))
    #expect(msg.contains("subject-specific template"))
    #expect(msg.contains("Pythagorean") == false)
}

@Test func guidedTargetFollowUpMessageMatchesClickToAdvanceContract() {
    let context = DesktopContextSnapshot(
        app: .init(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", processIdentifier: 123),
        window: nil,
        screen: nil,
        browser: .init(title: "Demo", url: "http://127.0.0.1/demo")
    )
    let msg = ClippyAgentInstructions.guidedTargetFollowUpMessage(
        label: "Add button",
        trigger: "clicked",
        triggerPointX: 420,
        triggerPointY: 360,
        round: 2,
        remainingRounds: 0,
        screenshotPath: "/tmp/shot.png",
        screenshotPixelWidth: 1600,
        screenshotPixelHeight: 1034,
        desktopContext: context
    )
    #expect(msg.contains("Guided target follow-up"))
    #expect(msg.contains("clicked the guided target \"Add button\""))
    #expect(msg.contains("/tmp/shot.png (1600x1034 px)"))
    #expect(msg.contains("remaining click-to-advance turns after this response: 0"))
    #expect(msg.contains("If another visible step is useful"))
    #expect(msg.contains("If the task is complete"))
    #expect(msg.contains("do not emit [TARGET] or [HOVER]"))
}

@Test func screenshotPolicyCapturesEveryTurn() {
    #expect(ClippyAgentInstructions.shouldAttachScreenshot(text: "Say exactly: perf ok.", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldAttachScreenshot(text: "what's on my screen", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldAttachScreenshot(text: "highlight this button", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldAttachScreenshot(text: "fix that", inputMode: .voice))
    #expect(ClippyAgentInstructions.shouldAttachScreenshot(text: "summarize the docs", inputMode: .voice))
}

@Test func computerControlPolicyRoutesGuiWorkToCodexLane() {
    #expect(ClippyAgentInstructions.shouldUseComputerControl(text: "fill out this application form", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseComputerControl(text: "fill it out right away", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseComputerControl(text: "apply to this job in the browser", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseComputerControl(text: "click the blue button", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseComputerControl(text: "Guide me to click the Start demo button. Mark it as the click target and continue after I click it.", inputMode: .text) == false)
    #expect(ClippyAgentInstructions.shouldUseComputerControl(text: "type this into the page", inputMode: .voice))
    #expect(ClippyAgentInstructions.shouldUseComputerControl(text: "hover over that menu", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseComputerControl(text: "hover a ring over this button", inputMode: .text) == false)
    #expect(ClippyAgentInstructions.shouldUseComputerControl(text: "summarize the docs", inputMode: .voice) == false)
    #expect(ClippyAgentInstructions.shouldUseComputerControl(text: "what's on my screen", inputMode: .text) == false)
}

@Test func codexToolLaneRoutesScreenAnnotationWork() {
    #expect(ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: "highlight this button", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: "draw an arrow on the page", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: "Can you draw my screen to explain this?", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: "draw over this page", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: "draw", inputMode: .voice))
    #expect(ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: "point at the menu", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: "circle this", inputMode: .voice))
    #expect(ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: "Guide me to click the Start demo button. Mark it as the click target and continue after I click it.", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseScreenAnnotationTool(text: "draw a logo", inputMode: .text) == false)

    #expect(ClippyAgentInstructions.shouldUseCodexToolLane(text: "highlight this button", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseCodexToolLane(text: "Can you draw my screen to explain this?", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseCodexToolLane(text: "show me where to click", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseCodexToolLane(text: "fill out this form", inputMode: .text))
    #expect(ClippyAgentInstructions.shouldUseCodexToolLane(text: "summarize the docs", inputMode: .text) == false)
}

@Test func computerUsePromptDisablesCuaCursorForVisibleActions() {
    #expect(ClippyAgentInstructions.systemPrompt.contains("Cua's own agent-cursor overlay is disabled in Clippy"))
    #expect(ClippyAgentInstructions.systemPrompt.contains("The visible cursor is Clippy's body"))
    #expect(ClippyAgentInstructions.systemPrompt.contains("Clippy-style inline grounding tags"))
    #expect(ClippyAgentInstructions.systemPrompt.contains("Pythagorean") == false)
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
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-codex-prepare-\(UUID().uuidString).txt")
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

@Test func computerUseMCPConfigPrefersExplicitCuaDriver() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-cua-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cua = tempDir.appendingPathComponent("cua-driver")
    FileManager.default.createFile(atPath: cua.path, contents: Data("#!/bin/sh\n".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cua.path)

    let runtime = ComputerUseMCPConfig.defaultRuntime(environment: ["CLIPPY_CUA_DRIVER": cua.path])
    #expect(runtime?.serverName == "cua-driver")
    #expect(runtime?.command == cua.path)
    #expect(runtime?.args == ["mcp", "--no-daemon-relaunch", "--no-overlay"])
    #expect(runtime?.enabledTools.contains("drag") == true)
    #expect(runtime?.enabledTools.contains("move_cursor") == false)
    #expect(runtime?.enabledTools.contains("set_agent_cursor_style") == false)
    #expect(runtime?.enabledTools.contains("get_agent_cursor_state") == false)
    #expect(runtime?.enabledTools.contains("zoom") == true)
    #expect(runtime?.enabledTools.contains("screenshot") == false)
    #expect(ComputerUseMCPConfig.clippyEnabledTools.contains("screenshot"))
    #expect(ComputerUseMCPConfig.clippyEnabledTools.contains("drag") == false)
    #expect(ComputerUseMCPConfig.clippyEnabledTools.contains("set_agent_cursor_enabled") == false)

    let overrides = ComputerUseMCPConfig.codexConfigOverrides(for: [try #require(runtime)])
    #expect(overrides.contains { $0.contains("mcp_servers.cua-driver.command") && $0.contains(cua.path) })
    #expect(overrides.contains { $0.contains("mcp_servers.cua-driver.enabled_tools") && $0.contains("get_window_state") })
}

@Test func computerUseMCPConfigPrefersBundledHelperOverExternalInstall() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-bundled-cua-\(UUID().uuidString)", isDirectory: true)
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
    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-codex-mcp-\(UUID().uuidString).txt")
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
        annotationRuntime: MCPServerRuntime(serverName: "clippy-annotation", command: "/tmp/ClippyMCP", enabledTools: ["annotate"]),
        diagnosticsLogURL: nil
    )

    let turn = await conversation.send("use tools")
    #expect(turn.text == "OK")

    let logged = try String(contentsOf: logURL, encoding: .utf8)
    #expect(logged.contains("mcp_servers.cua-driver.command"))
    #expect(logged.contains("mcp_servers.clippy-annotation.command"))
    #expect(logged.contains(#""cua-driver""#))
    #expect(logged.contains(#""clippy-annotation""#))
    #expect(logged.contains(#""enabled_tools":["click"]"#))
    #expect(logged.contains(#""enabled_tools":["annotate"]"#))
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
        case .partial(let text):
            firstPartial = text
            break streamLoop
        case .final:
            Issue.record("Expected Codex app-server agentMessage delta to arrive before the completed item.")
            return
        }
    }

    #expect(statuses.contains("Thinking"))
    #expect(statuses.contains("Opening the Clippy thread"))
    #expect(statuses.contains("Sending the turn"))
    #expect(firstPartial == "EARLY ")
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
        .appendingPathComponent("clippy-codex-diagnostics-\(UUID().uuidString).log")
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

@Test func clippyUserFacingErrorHidesInternalComputerUseFailures() {
    let raw = "The Cua computer-use bridge is not connected in this session, so I can't click and type."
    let friendly = ClippyUserFacingError.replacement(for: raw, isError: false)

    #expect(friendly == "I hit a local computer-control error. I saved the details in Clippy Logs.")
    #expect(friendly?.contains("Cua") == false)
    #expect(friendly?.contains("MCP") == false)
    #expect(friendly?.contains("bridge") == false)
    #expect(friendly?.contains("session") == false)
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

@Test func clippySpecOwnsBubbleCopyAndActivityAnimations() throws {
    let spec = ClippySpec.current

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
    let balloonLayer = ClippyBalloonStyle.makeShapeLayer(spec: spec.balloon)
    #expect(balloonLayer.allowsEdgeAntialiasing)
    #expect(balloonLayer.lineJoin == .round)
    let fill = try #require(spec.balloon.fillColor.usingColorSpace(.deviceRGB))
    #expect(fill.redComponent > 0.99)
    #expect(fill.greenComponent > 0.99)
    #expect(fill.blueComponent < fill.redComponent)
}

@Test func bubbleAutoHideDurationScalesWithReadingTime() {
    let short = ClippyBubbleController.readingAutoHideDelay(for: "Need a hand?")
    let medium = ClippyBubbleController.readingAutoHideDelay(
        for: Array(repeating: "word", count: 40).joined(separator: " "))
    let veryLong = ClippyBubbleController.readingAutoHideDelay(
        for: Array(repeating: "word", count: 200).joined(separator: " "))

    #expect(short == 3.5)
    #expect(medium > short)
    #expect(medium < veryLong)
    #expect(veryLong == 24.0)
}

@Test func spokenBubbleKeepsAVisibleGraceAfterSpeechEnds() {
    #expect(ClippyBubbleController.spokenAutoHideDelay(visibleFor: 0) == 4.0)
    #expect(ClippyBubbleController.spokenAutoHideDelay(visibleFor: 1.5) == 2.5)
    #expect(ClippyBubbleController.spokenAutoHideDelay(visibleFor: 4.0) == 2.0)
    #expect(ClippyBubbleController.spokenAutoHideDelay(visibleFor: 20.0) == 2.0)
}

@Test func bubbleChoiceKeyboardShortcutsSelectAndActivateChoices() {
    #expect(ClippyChoiceKeyboard.action(
        keyCode: 36,
        charactersIgnoringModifiers: "\r",
        selectedIndex: 1,
        choiceCount: 3
    ) == .activate(1))
    #expect(ClippyChoiceKeyboard.action(
        keyCode: 18,
        charactersIgnoringModifiers: "1",
        selectedIndex: 2,
        choiceCount: 3
    ) == .activate(0))
    #expect(ClippyChoiceKeyboard.action(
        keyCode: 20,
        charactersIgnoringModifiers: "3",
        selectedIndex: 0,
        choiceCount: 3
    ) == .activate(2))
    #expect(ClippyChoiceKeyboard.action(
        keyCode: 125,
        charactersIgnoringModifiers: nil,
        selectedIndex: 2,
        choiceCount: 3
    ) == .select(0))
    #expect(ClippyChoiceKeyboard.action(
        keyCode: 126,
        charactersIgnoringModifiers: nil,
        selectedIndex: nil,
        choiceCount: 3
    ) == .select(2))
    #expect(ClippyChoiceKeyboard.action(
        keyCode: 53,
        charactersIgnoringModifiers: "\u{1B}",
        selectedIndex: 0,
        choiceCount: 3
    ) == .cancel)
}

@Test func annotationPaletteUsesSingleYellowStrokeUnlessBackgroundIsLight() {
    #expect(AnnotationPalette.backingTone(luminance: 0.12, fallbackAppearance: .init(named: .darkAqua)!) == nil)
    #expect(AnnotationPalette.backingTone(luminance: 0.55, fallbackAppearance: .init(named: .darkAqua)!) == nil)
    #expect(AnnotationPalette.backingTone(luminance: 0.82, fallbackAppearance: .init(named: .darkAqua)!) == .dark)
    #expect(AnnotationPalette.backingTone(luminance: nil, fallbackAppearance: .init(named: .darkAqua)!) == nil)
    #expect(AnnotationPalette.backingTone(luminance: nil, fallbackAppearance: .init(named: .aqua)!) == .dark)
}

@Test func clippyBodyScaleClampsAndStepsInQuarterIncrements() {
    #expect(ClippyBodyScale(0.1).value == ClippyBodyScale.minimum)
    #expect(ClippyBodyScale(9).value == ClippyBodyScale.maximum)
    #expect(ClippyBodyScale.default.adjusted(by: 1).value == 1.25)
    #expect(ClippyBodyScale.default.adjusted(by: -1).value == 0.75)
    #expect(ClippyBodyScale(1.25).rasterScale == 2.5)
    #expect(ClippyBodyScale(1.25).percentTitle == "125%")
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

@Test func clippySpriteSheetFramesReuseCachedTextures() throws {
    let root = clippyResourceRoot()
    let sheet = try ClippySpriteSheet(packRoot: root)
    let animation = try #require(sheet.pack.animations["RestPose"])
    let frame = try #require(animation.frames.first)
    let cached = try #require(sheet.texture(for: frame))
    let frames = try #require(sheet.frames(for: "RestPose"))
    let first = try #require(frames.textures.first)

    #expect(first === cached)
}

@Test func clippySpriteSheetPreloadsAnimationTexturesThroughTheCache() throws {
    let root = clippyResourceRoot()
    let sheet = try ClippySpriteSheet(packRoot: root)
    let count = sheet.preloadTextures(for: ["Processing", "RestPose"])
    let animation = try #require(sheet.pack.animations["Processing"])
    let frame = try #require(animation.frames.first)
    let cached = try #require(sheet.texture(for: frame))
    let frames = try #require(sheet.frames(for: "Processing"))
    let first = try #require(frames.textures.first)

    #expect(count > 1)
    #expect(first === cached)
}

@Test @MainActor func clippyAnimatorStopsAfterOneShotAnimationExits() throws {
    let root = clippyResourceRoot()
    let sheet = try ClippySpriteSheet(packRoot: root)
    let renderer = SpriteKitRasterCharacterRenderer(size: sheet.frameSize)
    let animator = ClippyAnimator(sheet: sheet, renderer: renderer)
    var ended = false

    #expect(animator.play("RestPose") { _, state in
        ended = state == .exited
    })

    #expect(ended)
    #expect(animator.isAnimationRunning == false)
}

@Test @MainActor func clippyWindowMoveReportsFrameChanges() {
    let controller = ClippyWindowController(
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

@Test @MainActor func spriteRendererResizeUpdatesViewAndSpriteAnchor() {
    let renderer = SpriteKitRasterCharacterRenderer(size: CGSize(width: 24, height: 24))

    renderer.resize(to: CGSize(width: 48, height: 36))

    #expect(renderer.view.frame.size == CGSize(width: 48, height: 36))
    #expect(renderer.scene.scaleMode == .resizeFill)
    #expect(renderer.sprite.position == CGPoint(x: 24, y: 0))
}

@Test @MainActor func clippyWindowDisablesCompetingBackgroundDrag() {
    let controller = ClippyWindowController(
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

@Test func voiceEventsDriveClippyState() throws {
    var machine = ClippyStateMachine(initialState: .idle)

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
    let anthropic = try #require(catalog.descriptor(for: .anthropic))
    let openAI = try #require(catalog.descriptor(for: .openAI))
    let deepgram = try #require(catalog.descriptor(for: .deepgram))
    let xai = try #require(catalog.descriptor(for: .xAI))

    #expect(anthropic.environmentVariable == "ANTHROPIC_API_KEY")
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
    #expect(CredentialCatalog.clippySecretsPath.hasSuffix("/Library/Application Support/Clippy/Secrets.json"))
    #expect(CredentialCatalog.irisSettingsPath.hasSuffix("/Library/Application Support/Iris/settings.json"))
    #expect(CredentialCatalog.irisNativePreferencesPath.hasSuffix("/Library/Preferences/ai.companion.iris.mac.plist"))
}

@Test func localBrainAPIKeysAreInjectedFromClippyAndIrisStores() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretsURL = directory.appendingPathComponent("Secrets.json")
    let irisURL = directory.appendingPathComponent("settings.json")
    try """
    {
      "anthropicAPIKey": "anthropic-from-clippy",
      "openAIAPIKey": ""
    }
    """.write(to: secretsURL, atomically: true, encoding: .utf8)
    try """
    {
      "providerKeys": {
        "openaiApiKey": "openai-from-iris"
      }
    }
    """.write(to: irisURL, atomically: true, encoding: .utf8)

    let environment = ClippySecrets.environmentByAddingLocalAPIKeys(
        to: [
            "ANTHROPIC_API_KEY": "",
        ],
        secretsFileURL: secretsURL,
        irisSettingsURL: irisURL,
        nativePreferenceReader: { _ in nil }
    )

    #expect(environment["ANTHROPIC_API_KEY"] == "anthropic-from-clippy")
    #expect(environment["OPENAI_API_KEY"] == "openai-from-iris")
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
    #expect(config.workingDirectoryPath.hasSuffix("/Library/Application Support/Clippy/VoiceSidecar/iris-voice"))
    #expect(status["DEEPGRAM_API_KEY"] == "present")
    #expect(status["OPENAI_API_KEY"] == "missing")
    #expect(status["ANTHROPIC_API_KEY"] == "missing")
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
    #expect(VoiceSpeechTags.instruction.contains("[chuckle]"))
    #expect(VoiceSpeechTags.instruction.contains("<whisper>"))
    #expect(VoiceSpeechTags.instruction.contains("avoid deep"))
}

@Test func clippyVoiceCatalogUsesOnlyLiveXAIWomanAndManVoices() {
    #expect(ClippyVoice.default.id == "eve")
    #expect(ClippyVoice.all.map(\.id) == ["eve", "leo"])
    #expect(ClippyVoice.eve.displayName == "Eve")
    #expect(ClippyVoice.eve.detail == "Female · Multilingual")
    #expect(ClippyVoice.leo.displayName == "Leo")
    #expect(ClippyVoice.leo.detail == "Male · Multilingual")
    #expect(ClippyVoice.by(id: "grace") == nil)
    #expect(ClippyVoice.by(id: "daniel") == nil)
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
