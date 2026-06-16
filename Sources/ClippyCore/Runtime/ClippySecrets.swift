import Foundation

/// Loads local API keys so Clippy can call providers directly (no cloud proxy).
/// Reads the process environment first, then Clippy's local secrets file, then
/// Iris' local settings/preferences so installed apps can share already-entered
/// provider keys without copying them by hand.
public enum ClippySecrets {
    /// Deepgram key — used for streaming speech-to-text.
    public static var deepgramAPIKey: String? {
        resolve(
            fileKeys: ["deepgramAPIKey", "deepgramApiKey"],
            environmentKeys: ["DEEPGRAM_API_KEY"],
            irisSettingsKeyPath: "providerKeys.deepgramApiKey",
            irisNativePreferenceKey: "providerKeys.deepgram-api-key"
        )
    }

    /// xAI key — used for Grok text-to-speech.
    public static var xaiAPIKey: String? {
        resolve(
            fileKeys: ["xaiAPIKey", "xaiApiKey", "xAIAPIKey"],
            environmentKeys: ["XAI_API_KEY", "IRIS_XAI_API_KEY", "GROK_API_KEY"],
            irisSettingsKeyPath: "providerKeys.xaiApiKey",
            irisNativePreferenceKey: "providerKeys.xai-api-key"
        )
    }

    public static var secretsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Clippy", isDirectory: true)
            .appendingPathComponent("Secrets.json")
    }

    public static var missingRequiredProviderNames: [String] {
        var names: [String] = []
        if deepgramAPIKey == nil { names.append("Deepgram") }
        if xaiAPIKey == nil { names.append("xAI") }
        return names
    }

    public static func saveProviderKeys(deepgramAPIKey: String?, xaiAPIKey: String?) throws {
        var object = readObject(at: secretsFileURL) as? [String: Any] ?? [:]
        set(deepgramAPIKey, for: "deepgramAPIKey", in: &object)
        set(xaiAPIKey, for: "xaiAPIKey", in: &object)

        let directory = secretsFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: secretsFileURL, options: [.atomic])
    }

    private static func resolve(
        fileKeys: [String],
        environmentKeys: [String],
        irisSettingsKeyPath: String,
        irisNativePreferenceKey: String
    ) -> String? {
        for key in environmentKeys {
            if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        if let object = readObject(at: secretsFileURL) {
            for key in fileKeys {
                if let value = nestedString(in: object, keyPath: key) {
                    return value
                }
            }
        }

        if let object = readObject(at: irisSettingsURL),
           let value = nestedString(in: object, keyPath: irisSettingsKeyPath) {
            return value
        }

        if let value = readNativePreference(key: irisNativePreferenceKey) {
            return value
        }
        return nil
    }

    private static var irisSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Iris/settings.json")
    }

    private static var irisNativePreferencesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/ai.companion.iris.mac.plist")
    }

    private static func set(_ value: String?, for key: String, in object: inout [String: Any]) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            object.removeValue(forKey: key)
        } else {
            object[key] = trimmed
        }
    }

    private static func readObject(at url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func nestedString(in object: Any, keyPath: String) -> String? {
        let parts = keyPath.split(separator: ".").map(String.init)
        var current: Any? = object
        for part in parts {
            guard let dictionary = current as? [String: Any] else { return nil }
            current = dictionary[part]
        }
        let value = (current as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func readNativePreference(key: String) -> String? {
        if let defaults = UserDefaults(suiteName: "ai.companion.iris.mac"),
           let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        guard let plist = NSDictionary(contentsOf: irisNativePreferencesURL),
              let value = (plist[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
