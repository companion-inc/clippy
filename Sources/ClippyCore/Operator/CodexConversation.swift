import Foundation

/// Clippy's brain via the local OpenAI Codex CLI (`codex exec`) — used for GPT-5.5.
/// Each turn runs a fresh non-interactive exec at low reasoning effort and reads the
/// final assistant message from `--output-last-message`. Stateless per turn for now
/// (no cross-turn session; the Claude backend keeps history via `--resume`).
public actor CodexConversation: AgentBrain {
    private let binaryPath: String
    private let model: String
    private let effort: String
    private let workingDirectory: String?
    private let systemPrompt: String?

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

        var arguments = [
            "exec",
            "-m", model,
            "-c", "model_reasoning_effort=\(effort)",
            "--dangerously-bypass-approvals-and-sandbox",
            "--skip-git-repo-check",
            "-o", outputFile,
        ]
        if let workingDirectory {
            arguments.append(contentsOf: ["-C", workingDirectory])
        }
        arguments.append(prompt)

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
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = (try? String(contentsOfFile: outputFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try? FileManager.default.removeItem(atPath: outputFile)
        if text.isEmpty {
            return AgentTurn(text: "Codex returned nothing (model \(model)).", isError: true)
        }
        return AgentTurn(text: text, isError: false)
    }
}
