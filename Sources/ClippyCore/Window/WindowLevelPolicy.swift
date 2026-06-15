import AppKit

public enum WindowLevelPolicy {
    public static var clippyLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
    }

    public static var bubbleLevel: NSWindow.Level {
        NSWindow.Level(rawValue: clippyLevel.rawValue + 1)
    }
}
