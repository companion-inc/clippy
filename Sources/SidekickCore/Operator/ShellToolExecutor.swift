import Foundation

/// Executes a read-mostly shell command on the user's Mac. Registered under the
/// `shell.exec` tool name, which `ApprovalPolicy` gates as `.shell` — so the
/// assistant loop pauses for user approval before this ever runs.
public struct ShellToolExecutor: ToolExecuting {
    private let maxOutputBytes: Int

    public init(maxOutputBytes: Int = 8000) {
        self.maxOutputBytes = maxOutputBytes
    }

    public func execute(_ invocation: ToolInvocation) async -> ToolResult {
        guard case let .string(command)? = invocation.arguments["command"] else {
            return ToolResult(
                invocationID: invocation.id,
                toolName: invocation.name,
                status: .failed,
                summary: "shell.exec requires a 'command' string argument."
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ToolResult(
                invocationID: invocation.id,
                toolName: invocation.name,
                status: .failed,
                summary: "Failed to launch command: \(error.localizedDescription)"
            )
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var output = String(data: data, encoding: .utf8) ?? ""
        if output.count > maxOutputBytes {
            output = String(output.prefix(maxOutputBytes)) + "\n…(truncated)"
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output = "(no output)"
        }

        let status: ToolResultStatus = process.terminationStatus == 0 ? .succeeded : .failed
        return ToolResult(
            invocationID: invocation.id,
            toolName: invocation.name,
            status: status,
            summary: output,
            payload: .object([
                "exitCode": .number(Double(process.terminationStatus)),
                "command": .string(command),
            ])
        )
    }
}
