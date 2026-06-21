import AppKit

public enum WindowLevelPolicy {
    public static var sidekickLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
    }

    public static var bubbleLevel: NSWindow.Level {
        NSWindow.Level(rawValue: sidekickLevel.rawValue + 1)
    }
}
