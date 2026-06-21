import Foundation

public enum CredentialProvider: String, CaseIterable, Codable, Equatable, Sendable {
    case anthropic
    case deepgram
    case gemini
    case openAI
    case xAI
}

public enum CredentialSourceKind: String, Codable, Equatable, Sendable {
    case environment
    case sidekickSecretsJSON
    case clippySecretsJSON
    case irisSettingsJSON
    case nativePreferences
}

public struct CredentialSourceDescriptor: Codable, Equatable, Sendable {
    public let kind: CredentialSourceKind
    public let path: String?
    public let keyPath: String?

    public init(kind: CredentialSourceKind, path: String? = nil, keyPath: String? = nil) {
        self.kind = kind
        self.path = path
        self.keyPath = keyPath
    }
}

public struct CredentialDescriptor: Codable, Equatable, Sendable {
    public let provider: CredentialProvider
    public let environmentVariable: String
    public let sources: [CredentialSourceDescriptor]

    public init(
        provider: CredentialProvider,
        environmentVariable: String,
        sources: [CredentialSourceDescriptor]
    ) {
        self.provider = provider
        self.environmentVariable = environmentVariable
        self.sources = sources
    }
}

public struct CredentialCatalog: Codable, Equatable, Sendable {
    public let descriptors: [CredentialDescriptor]

    public init(descriptors: [CredentialDescriptor] = CredentialCatalog.defaultDescriptors) {
        self.descriptors = descriptors
    }

    public func descriptor(for provider: CredentialProvider) -> CredentialDescriptor? {
        descriptors.first { $0.provider == provider }
    }
}

public extension CredentialCatalog {
    static var irisSettingsPath: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/Iris/settings.json"
    }

    static var sidekickSecretsPath: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/Sidekick/Secrets.json"
    }

    static var clippySecretsPath: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/Clippy/Secrets.json"
    }

    static var irisNativePreferencesPath: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Preferences/ai.companion.iris.mac.plist"
    }

    static let defaultDescriptors: [CredentialDescriptor] = [
        CredentialDescriptor(
            provider: .anthropic,
            environmentVariable: "ANTHROPIC_API_KEY",
            sources: [
                CredentialSourceDescriptor(kind: .environment, keyPath: "ANTHROPIC_API_KEY"),
                CredentialSourceDescriptor(kind: .sidekickSecretsJSON, path: sidekickSecretsPath, keyPath: "anthropicAPIKey"),
                CredentialSourceDescriptor(kind: .clippySecretsJSON, path: clippySecretsPath, keyPath: "anthropicAPIKey"),
                CredentialSourceDescriptor(kind: .irisSettingsJSON, path: irisSettingsPath, keyPath: "providerKeys.anthropicApiKey"),
                CredentialSourceDescriptor(kind: .nativePreferences, path: irisNativePreferencesPath, keyPath: "providerKeys.anthropic-api-key"),
            ]
        ),
        CredentialDescriptor(
            provider: .deepgram,
            environmentVariable: "DEEPGRAM_API_KEY",
            sources: [
                CredentialSourceDescriptor(kind: .environment, keyPath: "DEEPGRAM_API_KEY"),
                CredentialSourceDescriptor(kind: .sidekickSecretsJSON, path: sidekickSecretsPath, keyPath: "sttAPIKey"),
                CredentialSourceDescriptor(kind: .clippySecretsJSON, path: clippySecretsPath, keyPath: "sttAPIKey"),
                CredentialSourceDescriptor(kind: .irisSettingsJSON, path: irisSettingsPath, keyPath: "providerKeys.deepgramApiKey"),
                CredentialSourceDescriptor(kind: .nativePreferences, path: irisNativePreferencesPath, keyPath: "providerKeys.deepgram-api-key"),
            ]
        ),
        CredentialDescriptor(
            provider: .gemini,
            environmentVariable: "GEMINI_API_KEY",
            sources: [
                CredentialSourceDescriptor(kind: .environment, keyPath: "GEMINI_API_KEY"),
                CredentialSourceDescriptor(kind: .irisSettingsJSON, path: irisSettingsPath, keyPath: "providerKeys.geminiApiKey"),
            ]
        ),
        CredentialDescriptor(
            provider: .openAI,
            environmentVariable: "OPENAI_API_KEY",
            sources: [
                CredentialSourceDescriptor(kind: .environment, keyPath: "OPENAI_API_KEY"),
                CredentialSourceDescriptor(kind: .sidekickSecretsJSON, path: sidekickSecretsPath, keyPath: "openAIAPIKey"),
                CredentialSourceDescriptor(kind: .clippySecretsJSON, path: clippySecretsPath, keyPath: "openAIAPIKey"),
                CredentialSourceDescriptor(kind: .irisSettingsJSON, path: irisSettingsPath, keyPath: "providerKeys.openaiApiKey"),
                CredentialSourceDescriptor(kind: .nativePreferences, path: irisNativePreferencesPath, keyPath: "providerKeys.openai-api-key"),
            ]
        ),
        CredentialDescriptor(
            provider: .xAI,
            environmentVariable: "XAI_API_KEY",
            sources: [
                CredentialSourceDescriptor(kind: .environment, keyPath: "XAI_API_KEY"),
                CredentialSourceDescriptor(kind: .sidekickSecretsJSON, path: sidekickSecretsPath, keyPath: "ttsAPIKey"),
                CredentialSourceDescriptor(kind: .clippySecretsJSON, path: clippySecretsPath, keyPath: "ttsAPIKey"),
                CredentialSourceDescriptor(kind: .irisSettingsJSON, path: irisSettingsPath, keyPath: "providerKeys.xaiApiKey"),
                CredentialSourceDescriptor(kind: .nativePreferences, path: irisNativePreferencesPath, keyPath: "providerKeys.xai-api-key"),
            ]
        ),
    ]
}
