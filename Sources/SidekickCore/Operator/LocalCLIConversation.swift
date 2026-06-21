import Foundation

/// A thread-safe holder for the running CLI subprocess. It lives outside the actor
/// so a barge-in can terminate the process directly — the actor itself is blocked
/// inside `process.waitUntilExit()` while a turn streams, so anything that has to
/// hop onto the actor (like an actor-isolated method) can't preempt it.
final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    func set(_ process: Process?) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
    }
    func terminate() {
        lock.lock(); defer { lock.unlock() }
        if let process, process.isRunning { process.terminate() }
        process = nil
    }
}

/// Sidekick's brain, running locally through the user's installed CLI. The first
/// turn opens a session; every later turn resumes it, so the local CLI holds the
/// full back-and-forth history, runs the agent loop, and executes tools on this Mac.
public actor LocalCLIConversation: StructuredOutputAgentBrain {
    public typealias Turn = AgentTurn

    private let binaryPath: String
    private let allowedTools: [String]
    private let permissionMode: String
    private let workingDirectory: String?
    private let systemPrompt: String?
    private let model: String?
    private let effort: String?
    private let sessionID = UUID().uuidString.uppercased()
    private var hasStarted = false

    public init(
        binaryPath: String,
        allowedTools: [String] = ["Bash", "Read", "Edit", "Write", "Glob", "Grep", "WebSearch", "WebFetch"],
        permissionMode: String = "acceptEdits",
        workingDirectory: String? = nil,
        systemPrompt: String? = SidekickAgentInstructions.systemPrompt,
        model: String? = SidekickModel.default.id,
        effort: String? = "low"
    ) {
        self.binaryPath = binaryPath
        self.allowedTools = allowedTools
        self.permissionMode = permissionMode
        self.workingDirectory = workingDirectory
        self.systemPrompt = systemPrompt
        self.model = model
        self.effort = effort
    }

    /// Best-effort discovery of the local CLI binary.
    public static func locateBinary() -> String? {
        if let managed = SidekickRuntimeLocator.claudeExecutablePath() {
            return managed
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to a login-shell lookup so PATH/aliases resolve.
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/zsh")
        probe.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        try? probe.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        probe.waitUntilExit()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    /// `--allowedTools` args. Visual grounding is NOT a tool —
    /// it's inline [POINT]/[TARGET]/[HIGHLIGHT]/[SHAPE] tags that ride inside the
    /// spoken reply so Sidekick talks *while* it acts, in one model pass. MCP is
    /// reserved for the real computer-use lane (get_window_state / click / set_value),
    /// which is result-dependent and doesn't exist yet. So no `--mcp-config` here.
    private func toolAndMCPArguments(localImagePaths: [String] = []) -> [String] {
        var tools = allowedTools
        if localImagePaths.isEmpty == false, tools.contains("Read") == false {
            tools.append("Read")
        }
        guard !tools.isEmpty else { return [] }
        return ["--allowedTools", tools.joined(separator: ",")]
    }

    private static func addDirArguments(for localImagePaths: [String]) -> [String] {
        let directories = localImagePaths
            .filter { $0.isEmpty == false }
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        let uniqueDirectories = Array(NSOrderedSet(array: directories)) as? [String] ?? directories
        guard uniqueDirectories.isEmpty == false else { return [] }
        return ["--add-dir"] + uniqueDirectories
    }

    private static func messageWithLocalImageReadInstructions(
        _ message: String,
        localImagePaths: [String]
    ) -> String {
        let paths = localImagePaths.filter { $0.isEmpty == false }
        guard paths.isEmpty == false else { return message }
        let bullets = paths.map { "- \($0)" }.joined(separator: "\n")
        return """
        [Local image context]
        Use the Read tool to inspect these local screenshot image files before answering. They are the current screen images for this turn:
        \(bullets)

        \(message)
        """
    }

    public func send(_ message: String) async -> Turn {
        await send(message, localImagePaths: [])
    }

    public func send(_ message: String, localImagePaths: [String]) async -> Turn {
        let message = Self.messageWithLocalImageReadInstructions(message, localImagePaths: localImagePaths)
        var arguments = [
            "-p", message,
            "--safe-mode",
            "--output-format", "json",
            "--permission-mode", permissionMode,
        ]
        arguments.append(contentsOf: Self.addDirArguments(for: localImagePaths))
        arguments.append(contentsOf: toolAndMCPArguments(localImagePaths: localImagePaths))
        if let systemPrompt, !systemPrompt.isEmpty {
            arguments.append(contentsOf: ["--append-system-prompt", systemPrompt])
        }
        if let model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        if let effort, !effort.isEmpty {
            arguments.append(contentsOf: ["--effort", effort])
        }
        if hasStarted {
            arguments.append(contentsOf: ["--resume", sessionID])
        } else {
            arguments.append(contentsOf: ["--session-id", sessionID])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        // The CLI's own permission alias must not leak in; pass a clean-ish env.
        var environment = SidekickSecrets.environmentByAddingLocalAPIKeys()
        environment["CLAUDE_CODE_ENTRYPOINT"] = "sidekick"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Turn(text: "I couldn't reach my local brain: \(error.localizedDescription)", isError: true, costUSD: nil)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        hasStarted = true

        guard let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any],
              let result = Self.resultText(from: json) else {
            let raw = String(data: outData, encoding: .utf8) ?? "no output"
            return Turn(text: "My local brain returned something I couldn't read.\n\(raw.prefix(200))", isError: true, costUSD: nil)
        }
        let isError = (json["is_error"] as? Bool) ?? false
        let cost = json["total_cost_usd"] as? Double
        return Turn(text: result, isError: isError, costUSD: cost)
    }

    public func sendStructured(
        _ message: String,
        localImagePaths: [String],
        outputSchema: AgentOutputSchema
    ) async -> Turn {
        guard let schema = Self.jsonString(from: outputSchema.jsonObject) else {
            return Turn(text: "I couldn't prepare the structured response schema.", isError: true, costUSD: nil)
        }

        let message = Self.messageWithLocalImageReadInstructions(message, localImagePaths: localImagePaths)
        var arguments = [
            "-p", message,
            "--safe-mode",
            "--output-format", "json",
            "--json-schema", schema,
            "--permission-mode", permissionMode,
        ]
        arguments.append(contentsOf: Self.addDirArguments(for: localImagePaths))
        arguments.append(contentsOf: toolAndMCPArguments(localImagePaths: localImagePaths))
        if let systemPrompt, !systemPrompt.isEmpty {
            arguments.append(contentsOf: ["--append-system-prompt", systemPrompt])
        }
        if let model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        if let effort, !effort.isEmpty {
            arguments.append(contentsOf: ["--effort", effort])
        }
        if hasStarted {
            arguments.append(contentsOf: ["--resume", sessionID])
        } else {
            arguments.append(contentsOf: ["--session-id", sessionID])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        var environment = SidekickSecrets.environmentByAddingLocalAPIKeys()
        environment["CLAUDE_CODE_ENTRYPOINT"] = "sidekick"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Turn(text: "I couldn't reach my local brain: \(error.localizedDescription)", isError: true, costUSD: nil)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        hasStarted = true

        guard let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any],
              let result = Self.structuredResultText(from: json) else {
            let raw = String(data: outData, encoding: .utf8) ?? "no output"
            return Turn(text: "My local brain returned something I couldn't read.\n\(raw.prefix(200))", isError: true, costUSD: nil)
        }
        let isError = (json["is_error"] as? Bool) ?? false
        let cost = json["total_cost_usd"] as? Double
        return Turn(text: result, isError: isError, costUSD: cost)
    }

    private static func resultText(from json: [String: Any]) -> String? {
        if let result = json["result"] as? String {
            return result
        }
        guard let result = json["result"],
              JSONSerialization.isValidJSONObject(result),
              let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text
    }

    private static func structuredResultText(from json: [String: Any]) -> String? {
        if let structured = json["structured_output"],
           JSONSerialization.isValidJSONObject(structured),
           let data = try? JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return resultText(from: json)
    }

    private static func jsonString(from object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Streaming (stream-json + partial text deltas)

    public nonisolated func stream(_ message: String) -> AsyncStream<AgentStreamChunk> {
        stream(message, localImagePaths: [])
    }

    public nonisolated func stream(_ message: String, localImagePaths: [String]) -> AsyncStream<AgentStreamChunk> {
        AsyncStream { continuation in
            let box = ProcessBox()
            let work = Task {
                await self.runStreaming(
                    message,
                    localImagePaths: localImagePaths,
                    continuation: continuation,
                    process: box
                )
            }
            // If the consumer cancels (barge-in: the user starts a new utterance),
            // tear down the work task and kill the underlying CLI subprocess directly
            // through the box, so it doesn't keep running and contend on the resumed
            // session. Going through the actor wouldn't work — it's blocked in
            // waitUntilExit() for the duration of the turn.
            continuation.onTermination = { @Sendable _ in
                work.cancel()
                box.terminate()
            }
        }
    }

    private func runStreaming(
        _ message: String,
        localImagePaths: [String],
        continuation: AsyncStream<AgentStreamChunk>.Continuation,
        process box: ProcessBox
    ) async {
        let message = Self.messageWithLocalImageReadInstructions(message, localImagePaths: localImagePaths)
        var arguments = [
            "-p", message,
            "--safe-mode",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--permission-mode", permissionMode,
        ]
        arguments.append(contentsOf: Self.addDirArguments(for: localImagePaths))
        arguments.append(contentsOf: toolAndMCPArguments(localImagePaths: localImagePaths))
        if let systemPrompt, !systemPrompt.isEmpty {
            arguments.append(contentsOf: ["--append-system-prompt", systemPrompt])
        }
        if let model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        if let effort, !effort.isEmpty {
            arguments.append(contentsOf: ["--effort", effort])
        }
        if hasStarted {
            arguments.append(contentsOf: ["--resume", sessionID])
        } else {
            arguments.append(contentsOf: ["--session-id", sessionID])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        var environment = SidekickSecrets.environmentByAddingLocalAPIKeys()
        environment["CLAUDE_CODE_ENTRYPOINT"] = "sidekick"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        continuation.yield(.status("Thinking"))
        do {
            try process.run()
        } catch {
            continuation.yield(.final(Turn(text: "I couldn't reach my local brain: \(error.localizedDescription)", isError: true)))
            continuation.finish()
            return
        }
        hasStarted = true
        box.set(process)
        continuation.yield(.status("Thinking"))

        var accumulated = ""
        var resultText: String?
        var isError = false
        var cost: Double?

        do {
            for try await line in outPipe.fileHandleForReading.bytes.lines {
                if Task.isCancelled { break }
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = object["type"] as? String else { continue }
                if type == "stream_event",
                   let event = object["event"] as? [String: Any],
                   (event["type"] as? String) == "content_block_delta",
                   let delta = event["delta"] as? [String: Any],
                   (delta["type"] as? String) == "text_delta",
                   let text = delta["text"] as? String {
                    accumulated += text
                    continuation.yield(.partial(accumulated))
                } else if type == "result" {
                    resultText = object["result"] as? String
                    isError = (object["is_error"] as? Bool) ?? false
                    cost = object["total_cost_usd"] as? Double
                }
            }
        } catch {
            // Stream read failed — fall through with whatever we accumulated.
        }
        _ = try? errPipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        box.set(nil)

        let finalText = (resultText?.isEmpty == false ? resultText! : accumulated)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if finalText.isEmpty {
            continuation.yield(.final(Turn(text: "My local brain returned nothing.", isError: true)))
        } else {
            continuation.yield(.final(Turn(text: finalText, isError: isError, costUSD: cost)))
        }
        continuation.finish()
    }
}
