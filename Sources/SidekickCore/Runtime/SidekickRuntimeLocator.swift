import Foundation

public enum SidekickRuntimeLocator {
    public static let codexVersion = "0.140.0"
    public static let claudeVersion = "2.1.181"

    public static func runtimesDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Sidekick", isDirectory: true)
            .appendingPathComponent("Runtimes", isDirectory: true)
    }

    public static func codexInstallDirectory(baseDirectory: URL = runtimesDirectory()) -> URL {
        baseDirectory
            .appendingPathComponent("Codex", isDirectory: true)
            .appendingPathComponent(codexVersion, isDirectory: true)
    }

    public static func claudeInstallDirectory(baseDirectory: URL = runtimesDirectory()) -> URL {
        baseDirectory
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent(claudeVersion, isDirectory: true)
    }

    public static func codexExecutableURL(baseDirectory: URL = runtimesDirectory()) -> URL {
        codexInstallDirectory(baseDirectory: baseDirectory)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: false)
    }

    public static func claudeExecutableURL(baseDirectory: URL = runtimesDirectory()) -> URL {
        claudeInstallDirectory(baseDirectory: baseDirectory)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("claude", isDirectory: false)
    }

    public static func codexExecutablePath(
        fileManager: FileManager = .default,
        baseDirectory: URL = runtimesDirectory()
    ) -> String? {
        executablePathIfPresent(codexExecutableURL(baseDirectory: baseDirectory), fileManager: fileManager)
    }

    public static func claudeExecutablePath(
        fileManager: FileManager = .default,
        baseDirectory: URL = runtimesDirectory()
    ) -> String? {
        executablePathIfPresent(claudeExecutableURL(baseDirectory: baseDirectory), fileManager: fileManager)
    }

    private static func executablePathIfPresent(_ url: URL, fileManager: FileManager) -> String? {
        fileManager.isExecutableFile(atPath: url.path) ? url.path : nil
    }
}
