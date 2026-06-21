import Foundation

public enum SidekickRecordReplayMCPConfig {
    public static let serverName = "sidekick-record-replay"
    public static let executableName = "SidekickRecordReplayMCP"

    public static let enabledTools = [
        "event_stream_start",
        "event_stream_status",
        "event_stream_stop",
    ]

    public static func defaultRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> MCPServerRuntime? {
        let candidates = executableCandidates(environment: environment)
        for path in candidates where !path.isEmpty {
            if fileManager.isExecutableFile(atPath: path) {
                return MCPServerRuntime(
                    serverName: serverName,
                    command: path,
                    enabledTools: enabledTools
                )
            }
        }
        return nil
    }

    private static func executableCandidates(environment: [String: String]) -> [String] {
        var candidates: [String] = []
        if let override = environment["SIDEKICK_RECORD_REPLAY_MCP"] ?? environment["CLIPPY_RECORD_REPLAY_MCP"], !override.isEmpty {
            candidates.append(override)
        }
        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent().path {
            candidates.append("\(executableDir)/\(executableName)")
        }
        let cwd = FileManager.default.currentDirectoryPath
        candidates.append("\(cwd)/.build/debug/\(executableName)")
        candidates.append("\(cwd)/.build/arm64-apple-macosx/debug/\(executableName)")
        candidates.append("\(cwd)/.build/x86_64-apple-macosx/debug/\(executableName)")
        return candidates
    }
}
