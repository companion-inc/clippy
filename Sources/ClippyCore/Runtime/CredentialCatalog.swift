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
    static let irisSettingsPath = "/Users/advaitpaliwal/Library/Application Support/Iris/settings.json"
    static let irisNativePreferencesPath = "/Users/advaitpaliwal/Library/Preferences/ai.companion.iris.mac.plist"

    static let defaultDescriptors: [CredentialDescriptor] = [
        CredentialDescriptor(
            provider: .anthropic,
            environmentVariable: "ANTHROPIC_API_KEY",
            sources: [
                CredentialSourceDescriptor(kind: .environment, keyPath: "ANTHROPIC_API_KEY"),
            ]
        ),
        CredentialDescriptor(
            provider: .deepgram,
            environmentVariable: "DEEPGRAM_API_KEY",
            sources: [
                CredentialSourceDescriptor(kind: .environment, keyPath: "DEEPGRAM_API_KEY"),
                CredentialSourceDescriptor(kind: .irisSettingsJSON, path: irisSettingsPath, keyPath: "providerKeys.deepgramApiKey"),
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
                CredentialSourceDescriptor(kind: .irisSettingsJSON, path: irisSettingsPath, keyPath: "providerKeys.openaiApiKey"),
            ]
        ),
        CredentialDescriptor(
            provider: .xAI,
            environmentVariable: "XAI_API_KEY",
            sources: [
                CredentialSourceDescriptor(kind: .environment, keyPath: "XAI_API_KEY"),
                CredentialSourceDescriptor(kind: .irisSettingsJSON, path: irisSettingsPath, keyPath: "providerKeys.xaiApiKey"),
            ]
        ),
    ]
}
