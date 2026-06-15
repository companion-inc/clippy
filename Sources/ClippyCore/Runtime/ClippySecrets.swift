import Foundation

/// Loads local API keys so Clippy can call providers directly (no cloud proxy).
/// Reads the process environment first, then `~/Library/Application Support/Clippy/Secrets.json`.
/// Format: `{ "deepgramAPIKey": "..." }`. Implemented for Clippy's LocalSecrets.
public enum ClippySecrets {
    private static let fileSecrets: [String: String] = readFile()

    /// Deepgram key — used for both streaming STT and Aura TTS.
    public static var deepgramAPIKey: String? {
        resolve(fileKey: "deepgramAPIKey", environmentKeys: ["DEEPGRAM_API_KEY"])
    }

    public static var secretsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Clippy", isDirectory: true)
            .appendingPathComponent("Secrets.json")
    }

    private static func resolve(fileKey: String, environmentKeys: [String]) -> String? {
        for key in environmentKeys {
            if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        if let value = fileSecrets[fileKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        return nil
    }

    private static func readFile() -> [String: String] {
        guard let data = try? Data(contentsOf: secretsFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return json
    }
}
