import Foundation

public enum SidekickAnnotationMCPConfig {
    public static func defaultRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> MCPServerRuntime? {
        let candidates = executableCandidates(environment: environment)
        for path in candidates where !path.isEmpty {
            if fileManager.isExecutableFile(atPath: path) {
                return MCPServerRuntime(
                    serverName: "sidekick-annotation",
                    command: path,
                    enabledTools: ["annotate", "clear_annotations", "outline_components"]
                )
            }
        }
        return nil
    }

    private static func executableCandidates(environment: [String: String]) -> [String] {
        var candidates: [String] = []
        if let override = environment["SIDEKICK_MCP"] ?? environment["CLIPPY_MCP"], !override.isEmpty {
            candidates.append(override)
        }
        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent().path {
            candidates.append("\(executableDir)/SidekickMCP")
        }
        let cwd = FileManager.default.currentDirectoryPath
        candidates.append("\(cwd)/.build/debug/SidekickMCP")
        candidates.append("\(cwd)/.build/arm64-apple-macosx/debug/SidekickMCP")
        candidates.append("\(cwd)/.build/x86_64-apple-macosx/debug/SidekickMCP")
        return candidates
    }
}
