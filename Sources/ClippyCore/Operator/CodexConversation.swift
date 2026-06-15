import Foundation

/// Clippy's brain via the local OpenAI Codex CLI (`codex exec`) — used for GPT-5.5.
/// The first turn opens a Codex thread; every later turn resumes that exact thread,
/// so GPT-5.5 keeps one shared conversation loop just like Claude.
public actor CodexConversation: AgentBrain {
    private let binaryPath: String
    private let model: String
    private let effort: String
    private let workingDirectory: String?
    private let systemPrompt: String?
    private var threadID: String?

    public init(
        binaryPath: String,
        model: String = "gpt-5.5",
        effort: String = "minimal",
        workingDirectory: String? = nil,
        systemPrompt: String? = ClippyAgentInstructions.systemPrompt
    ) {
        self.binaryPath = binaryPath
        self.model = model
        self.effort = effort
        self.workingDirectory = workingDirectory
        self.systemPrompt = systemPrompt
    }

    public static func locateBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/zsh")
        probe.arguments = ["-lc", "command -v codex"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        try? probe.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        probe.waitUntilExit()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    public func send(_ message: String) async -> AgentTurn {
        let outputFile = NSTemporaryDirectory() + "clippy-codex-\(UUID().uuidString).txt"
        let prompt = systemPrompt.map { "\($0)\n\n---\n\nUser: \(message)" } ?? message

        let arguments = commandArguments(prompt: prompt, outputFile: outputFile, json: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.environment = ProcessInfo.processInfo.environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return AgentTurn(text: "I couldn't reach Codex: \(error.localizedDescription)", isError: true)
        }
        _ = outPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var resumedThreadID = threadID
        var streamedText: String?
        Self.parseJSONLines(stdout, threadID: &resumedThreadID, finalText: &streamedText)
        threadID = resumedThreadID
        let text = finalText(from: outputFile, streamedText: streamedText)
        try? FileManager.default.removeItem(atPath: outputFile)
        if text.isEmpty {
            return AgentTurn(text: "Codex returned nothing (model \(model)).", isError: true)
        }
        return AgentTurn(text: text, isError: false)
    }

    public nonisolated func stream(_ message: String) -> AsyncStream<AgentStreamChunk> {
        AsyncStream { continuation in
            let box = ProcessBox()
            let work = Task { await self.runStreaming(message, continuation: continuation, process: box) }
            continuation.onTermination = { @Sendable _ in
                work.cancel()
                box.terminate()
            }
        }
    }

    private func runStreaming(
        _ message: String,
        continuation: AsyncStream<AgentStreamChunk>.Continuation,
        process box: ProcessBox
    ) async {
        let outputFile = NSTemporaryDirectory() + "clippy-codex-\(UUID().uuidString).txt"
        let prompt = systemPrompt.map { "\($0)\n\n---\n\nUser: \(message)" } ?? message
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = commandArguments(prompt: prompt, outputFile: outputFile, json: true)
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.environment = ProcessInfo.processInfo.environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            continuation.yield(.final(AgentTurn(text: "I couldn't reach Codex: \(error.localizedDescription)", isError: true)))
            continuation.finish()
            return
        }
        box.set(process)

        var resumedThreadID = threadID
        var streamedText: String?

        do {
            for try await line in outPipe.fileHandleForReading.bytes.lines {
                if Task.isCancelled { break }
                Self.parseJSONLine(String(line), threadID: &resumedThreadID, finalText: &streamedText)
            }
        } catch {
            // Fall through with whatever the CLI already wrote.
        }
        _ = try? errPipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        box.set(nil)

        threadID = resumedThreadID
        let text = finalText(from: outputFile, streamedText: streamedText)
        try? FileManager.default.removeItem(atPath: outputFile)
        if text.isEmpty {
            continuation.finish()
            return
        }
        continuation.yield(.final(AgentTurn(text: text, isError: false)))
        continuation.finish()
    }

    private func commandArguments(prompt: String, outputFile: String, json: Bool) -> [String] {
        var arguments = ["exec"]
        let resuming = threadID?.isEmpty == false
        if resuming {
            arguments.append("resume")
        }
        arguments.append(contentsOf: [
            "-m", model,
            "-c", "model_reasoning_effort=\(effort)",
            "--dangerously-bypass-approvals-and-sandbox",
            "--skip-git-repo-check",
            "-o", outputFile,
        ])
        if json {
            arguments.append("--json")
        }
        if let threadID, !threadID.isEmpty {
            arguments.append(threadID)
        }
        arguments.append(prompt)
        return arguments
    }

    private func finalText(from outputFile: String, streamedText: String?) -> String {
        let fileText = (try? String(contentsOfFile: outputFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fileText.isEmpty { return fileText }
        return streamedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func parseJSONLines(_ text: String, threadID: inout String?, finalText: inout String?) {
        for line in text.split(whereSeparator: \.isNewline) {
            parseJSONLine(String(line), threadID: &threadID, finalText: &finalText)
        }
    }

    private static func parseJSONLine(_ line: String, threadID: inout String?, finalText: inout String?) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }
        if type == "thread.started", let started = object["thread_id"] as? String, !started.isEmpty {
            threadID = started
            return
        }
        if type == "item.completed",
           let item = object["item"] as? [String: Any],
           (item["type"] as? String) == "agent_message",
           let text = item["text"] as? String,
           !text.isEmpty {
            finalText = text
        }
    }
}
