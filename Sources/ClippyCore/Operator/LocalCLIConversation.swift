import Foundation

/// Clippy's brain, running locally through the user's installed CLI. The first
/// turn opens a session; every later turn resumes it, so the local CLI holds the
/// full back-and-forth history, runs the agent loop, and executes tools on this Mac.
public actor LocalCLIConversation: AgentBrain {
    public typealias Turn = AgentTurn

    private let binaryPath: String
    private let allowedTools: [String]
    private let permissionMode: String
    private let workingDirectory: String?
    private let sessionID = UUID().uuidString.uppercased()
    private var hasStarted = false

    public init(
        binaryPath: String,
        allowedTools: [String] = ["Bash", "Read", "Edit", "Write", "Glob", "Grep", "WebSearch", "WebFetch"],
        permissionMode: String = "acceptEdits",
        workingDirectory: String? = nil
    ) {
        self.binaryPath = binaryPath
        self.allowedTools = allowedTools
        self.permissionMode = permissionMode
        self.workingDirectory = workingDirectory
    }

    /// Best-effort discovery of the local CLI binary.
    public static func locateBinary() -> String? {
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

    public func send(_ message: String) async -> Turn {
        var arguments = [
            "-p", message,
            "--output-format", "json",
            "--permission-mode", permissionMode,
        ]
        if !allowedTools.isEmpty {
            arguments.append(contentsOf: ["--allowedTools", allowedTools.joined(separator: ",")])
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
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CODE_ENTRYPOINT"] = "clippy"
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

        guard
            let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any],
            let result = json["result"] as? String
        else {
            let raw = String(data: outData, encoding: .utf8) ?? "no output"
            return Turn(text: "My local brain returned something I couldn't read.\n\(raw.prefix(200))", isError: true, costUSD: nil)
        }
        let isError = (json["is_error"] as? Bool) ?? false
        let cost = json["total_cost_usd"] as? Double
        return Turn(text: result, isError: isError, costUSD: cost)
    }
}
