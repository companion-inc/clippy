import Foundation

public enum FullDiskAccessPermission {
    public static var isGranted: Bool {
        databaseProbeURLs().contains { canOpenForRead($0) }
    }

    public static func databaseProbeURLs(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            home.appending(path: "Library/Messages/chat.db"),
            home.appending(path: "Library/Safari/History.db"),
            home.appending(path: "Library/Application Support/com.apple.TCC/TCC.db"),
        ]
    }

    private static func canOpenForRead(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            try? handle.close()
            return true
        } catch {
            return false
        }
    }
}
