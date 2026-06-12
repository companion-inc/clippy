import AppKit

public enum WindowLevelPolicy {
    public static var mascotLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
    }

    public static var bubbleLevel: NSWindow.Level {
        NSWindow.Level(rawValue: mascotLevel.rawValue + 1)
    }
}
