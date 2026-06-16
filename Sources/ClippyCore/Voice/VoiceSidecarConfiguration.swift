import Foundation

public struct VoiceSidecarConfiguration: Codable, Equatable, Sendable {
    public let executablePath: String
    public let workingDirectoryPath: String
    public let host: String
    public let port: Int
    public let wakeWord: String
    public let providerEnvironmentKeys: [String]

    public init(
        executablePath: String,
        workingDirectoryPath: String,
        host: String = "127.0.0.1",
        port: Int = 4748,
        wakeWord: String = "clippy",
        providerEnvironmentKeys: [String] = VoiceSidecarConfiguration.defaultProviderEnvironmentKeys
    ) {
        self.executablePath = executablePath
        self.workingDirectoryPath = workingDirectoryPath
        self.host = host
        self.port = port
        self.wakeWord = wakeWord
        self.providerEnvironmentKeys = providerEnvironmentKeys
    }

    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    public func environmentStatus(from environment: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: providerEnvironmentKeys.map { key in
            let value = environment[key]
            return (key, (value?.isEmpty == false) ? "present" : "missing")
        })
    }
}

public extension VoiceSidecarConfiguration {
    static let defaultProviderEnvironmentKeys = [
        "DEEPGRAM_API_KEY",
        "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY",
        "GEMINI_API_KEY",
        "XAI_API_KEY",
    ]

    static var irisVoiceSidecar: VoiceSidecarConfiguration {
        let environment = ProcessInfo.processInfo.environment
        return VoiceSidecarConfiguration(
            executablePath: environment["CLIPPY_VOICE_SIDECAR_EXECUTABLE"] ?? "uv",
            workingDirectoryPath: environment["CLIPPY_IRIS_VOICE_DIR"] ?? defaultIrisVoiceDirectoryPath
        )
    }

    private static var defaultIrisVoiceDirectoryPath: String {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("Clippy", isDirectory: true)
            .appendingPathComponent("VoiceSidecar", isDirectory: true)
            .appendingPathComponent("iris-voice", isDirectory: true)
            .path
    }
}
