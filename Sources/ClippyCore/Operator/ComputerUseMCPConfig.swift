import Foundation

public struct MCPServerRuntime: Equatable, Sendable {
    public let serverName: String
    public let command: String
    public let args: [String]
    public let startupTimeoutSeconds: Double
    public let enabledTools: [String]

    public init(
        serverName: String,
        command: String,
        args: [String] = [],
        startupTimeoutSeconds: Double = 20,
        enabledTools: [String] = []
    ) {
        self.serverName = serverName
        self.command = command
        self.args = args
        self.startupTimeoutSeconds = startupTimeoutSeconds
        self.enabledTools = enabledTools
    }

    public var codexServerConfig: [String: Any] {
        var config: [String: Any] = [
            "command": command,
            "args": args,
            "startup_timeout_sec": startupTimeoutSeconds,
        ]
        if !enabledTools.isEmpty {
            config["enabled_tools"] = enabledTools
        }
        return config
    }
}

public enum ComputerUseMCPConfig {
    public static let bundledHelperName = "ClippyComputerUseRuntime"

    public static let cuaDriverEnabledTools: [String] = [
        "check_permissions",
        "click",
        "double_click",
        "drag",
        "get_accessibility_tree",
        "get_config",
        "get_screen_size",
        "get_window_state",
        "hotkey",
        "launch_app",
        "list_apps",
        "list_windows",
        "page",
        "press_key",
        "right_click",
        "scroll",
        "set_config",
        "set_value",
        "type_text",
        "zoom",
    ]

    public static let clippyEnabledTools: [String] = [
        "check_permissions",
        "click",
        "get_config",
        "get_screen_size",
        "get_window_state",
        "hotkey",
        "launch_app",
        "list_apps",
        "list_windows",
        "page",
        "press_key",
        "right_click",
        "screenshot",
        "scroll",
        "set_config",
        "set_value",
        "type_text",
    ]

    public static let defaultEnabledTools = cuaDriverEnabledTools

    public static func cuaDriverArgs(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        executableDirectory: String? = Bundle.main.executableURL?.deletingLastPathComponent().path,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> [String] {
        ["mcp", "--no-daemon-relaunch", "--no-overlay"]
    }

    public static func defaultRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> MCPServerRuntime? {
        defaultRuntime(
            environment: environment,
            fileManager: fileManager,
            executableDirectory: Bundle.main.executableURL?.deletingLastPathComponent().path,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
    }

    public static func defaultRuntime(
        environment: [String: String],
        fileManager: FileManager = .default,
        executableDirectory: String? = Bundle.main.executableURL?.deletingLastPathComponent().path,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> MCPServerRuntime? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bundledCandidates = executableDirectory.map {
            [
                cleanPath("\($0)/../Helpers/\(bundledHelperName)"),
                cleanPath("\($0)/cua-driver"),
                cleanPath("\($0)/\(bundledHelperName)"),
            ]
        } ?? []
        let args = cuaDriverArgs(
            environment: environment,
            fileManager: fileManager,
            executableDirectory: executableDirectory,
            workingDirectory: workingDirectory
        )
        let candidates: [(serverName: String, command: String, args: [String], enabledTools: [String])] = [
            ("cua-driver", bundledCandidates.first ?? "", args, cuaDriverEnabledTools),
            ("cua-driver", bundledCandidates.dropFirst().first ?? "", args, cuaDriverEnabledTools),
            ("cua-driver", bundledCandidates.dropFirst(2).first ?? "", args, cuaDriverEnabledTools),
            ("cua-driver", environment["CLIPPY_CUA_DRIVER"] ?? "", args, cuaDriverEnabledTools),
            ("cua-driver", "\(workingDirectory)/.build/debug/\(bundledHelperName)", args, cuaDriverEnabledTools),
            ("cua-driver", "\(workingDirectory)/.build/arm64-apple-macosx/debug/\(bundledHelperName)", args, cuaDriverEnabledTools),
            ("cua-driver", "\(home)/.local/bin/cua-driver", args, cuaDriverEnabledTools),
            ("cua-driver", "/Applications/CuaDriver.app/Contents/MacOS/cua-driver", args, cuaDriverEnabledTools),
            ("computer-use", "/Applications/Clippy.app/Contents/Helpers/ClippyComputerUseRuntime", [], clippyEnabledTools),
        ]

        for candidate in candidates where !candidate.command.isEmpty {
            if fileManager.isExecutableFile(atPath: candidate.command) {
                return MCPServerRuntime(
                    serverName: candidate.serverName,
                    command: candidate.command,
                    args: candidate.args,
                    enabledTools: candidate.enabledTools
                )
            }
        }
        return nil
    }

    public static func codexConfigOverrides(for runtimes: [MCPServerRuntime]) -> [String] {
        guard !runtimes.isEmpty else { return ["mcp_servers={}"] }
        return runtimes.flatMap { runtime -> [String] in
            let prefix = "mcp_servers.\(runtime.serverName)"
            var overrides = [
                "\(prefix).command=\(tomlString(runtime.command))",
                "\(prefix).args=\(tomlArray(runtime.args))",
                "\(prefix).startup_timeout_sec=\(runtime.startupTimeoutSeconds)",
            ]
            if !runtime.enabledTools.isEmpty {
                overrides.append("\(prefix).enabled_tools=\(tomlArray(runtime.enabledTools))")
            }
            return overrides
        }
    }

    public static func codexThreadConfig(for runtimes: [MCPServerRuntime]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: runtimes.map { ($0.serverName, $0.codexServerConfig) })
    }

    private static func tomlArray(_ values: [String]) -> String {
        "[" + values.map(tomlString).joined(separator: ", ") + "]"
    }

    private static func cleanPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static func tomlString(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: escaped += "\\b"
            case 0x09: escaped += "\\t"
            case 0x0A: escaped += "\\n"
            case 0x0C: escaped += "\\f"
            case 0x0D: escaped += "\\r"
            case 0x22: escaped += "\\\""
            case 0x5C: escaped += "\\\\"
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }
}
