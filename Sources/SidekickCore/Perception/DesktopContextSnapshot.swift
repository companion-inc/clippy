import AppKit
import CoreGraphics
import Foundation

public struct DesktopContextSnapshot: Equatable, Sendable {
    public struct AppInfo: Equatable, Sendable {
        public let name: String
        public let bundleIdentifier: String?
        public let processIdentifier: Int

        public init(name: String, bundleIdentifier: String?, processIdentifier: Int) {
            self.name = name
            self.bundleIdentifier = bundleIdentifier
            self.processIdentifier = processIdentifier
        }
    }

    public struct WindowInfo: Equatable, Sendable {
        public let title: String?
        public let ownerName: String
        public let ownerProcessIdentifier: Int
        public let windowIdentifier: Int
        public let bounds: CGRect

        public init(
            title: String?,
            ownerName: String,
            ownerProcessIdentifier: Int,
            windowIdentifier: Int,
            bounds: CGRect
        ) {
            self.title = title
            self.ownerName = ownerName
            self.ownerProcessIdentifier = ownerProcessIdentifier
            self.windowIdentifier = windowIdentifier
            self.bounds = bounds
        }
    }

    public struct ScreenInfo: Equatable, Sendable {
        public let index: Int
        public let appKitFrame: CGRect
        public let displayBounds: CGRect
        public let displayIdentifier: UInt32

        public init(index: Int, appKitFrame: CGRect, displayBounds: CGRect, displayIdentifier: UInt32) {
            self.index = index
            self.appKitFrame = appKitFrame
            self.displayBounds = displayBounds
            self.displayIdentifier = displayIdentifier
        }
    }

    public struct BrowserInfo: Equatable, Sendable {
        public let title: String?
        public let url: String?

        public init(title: String?, url: String?) {
            self.title = title
            self.url = url
        }
    }

    public let app: AppInfo?
    public let window: WindowInfo?
    public let screen: ScreenInfo?
    public let browser: BrowserInfo?

    public init(app: AppInfo?, window: WindowInfo?, screen: ScreenInfo?, browser: BrowserInfo?) {
        self.app = app
        self.window = window
        self.screen = screen
        self.browser = browser
    }

    public static func capture(
        excludingProcessIdentifier excludedPID: Int = Int(ProcessInfo.processInfo.processIdentifier)
    ) -> DesktopContextSnapshot {
        let window = activeWindow(excludingProcessIdentifier: excludedPID)
        let app = appInfo(for: window) ?? fallbackFrontmostApp(excludingProcessIdentifier: excludedPID)
        let screen = window.flatMap { screenInfo(forWindowBounds: $0.bounds) }
        let browser = browserInfo(forBundleIdentifier: app?.bundleIdentifier)
        return DesktopContextSnapshot(app: app, window: window, screen: screen, browser: browser)
    }

    public func targetScreen(in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        guard let screen else { return nil }
        if let matched = screens.first(where: { Self.displayID(for: $0) == screen.displayIdentifier }) {
            return matched
        }
        guard screens.indices.contains(screen.index) else { return nil }
        return screens[screen.index]
    }

    public var promptBlock: String {
        var lines = ["[Current desktop context metadata captured before this turn:"]
        if let app {
            let bundle = app.bundleIdentifier ?? "unknown bundle"
            lines.append("- active app: \(app.name) (\(bundle), pid \(app.processIdentifier))")
        } else {
            lines.append("- active app: unknown")
        }
        if let window {
            lines.append(
                "- active window: title \(quoted(window.title)) id \(window.windowIdentifier) "
                + "owner \(window.ownerName) bounds \(format(window.bounds))"
            )
        } else {
            lines.append("- active window: unknown")
        }
        if let browser, browser.title != nil || browser.url != nil {
            lines.append("- browser tab title: \(quoted(browser.title))")
            lines.append("- browser tab url: \(browser.url ?? "unknown")")
        } else {
            lines.append("- browser tab url: unknown")
        }
        if let screen {
            lines.append(
                "- screenshot target screen: index \(screen.index) "
                + "appKitFrame \(format(screen.appKitFrame)) displayBounds \(format(screen.displayBounds)) "
                + "displayID \(screen.displayIdentifier)"
            )
        } else {
            lines.append("- screenshot target screen: fallback to Sidekick's display")
        }
        lines.append("Sidekick-owned windows are ignored when possible; use this for app/window/title/url context. Use a screenshot only when this turn includes one.]")
        return lines.joined(separator: "\n")
    }

    public var logSummary: String {
        let appName = app?.name ?? "unknown"
        let title = window?.title ?? "untitled"
        let screenIndex = screen.map { String($0.index) } ?? "fallback"
        let browserURL = browser?.url ?? "unknown"
        return "app=\(appName) window=\"\(title)\" screen=\(screenIndex) url=\(browserURL)"
    }

    public static func currentAppKitWindowFrame(
        ownerProcessIdentifier: Int,
        windowIdentifier: Int,
        excludingProcessIdentifier excludedPID: Int = Int(ProcessInfo.processInfo.processIdentifier)
    ) -> CGRect? {
        guard let window = visibleWindow(
            ownerProcessIdentifier: ownerProcessIdentifier,
            windowIdentifier: windowIdentifier,
            excludingProcessIdentifier: excludedPID
        ) else {
            return nil
        }
        return appKitFrame(for: window)
    }

    public static func isFrontmostWindow(
        ownerProcessIdentifier: Int,
        windowIdentifier: Int,
        excludingProcessIdentifier excludedPID: Int = Int(ProcessInfo.processInfo.processIdentifier)
    ) -> Bool {
        guard let window = activeWindow(excludingProcessIdentifier: excludedPID) else {
            return false
        }
        return window.ownerProcessIdentifier == ownerProcessIdentifier
            && window.windowIdentifier == windowIdentifier
    }

    public static func visibleWindow(
        ownerProcessIdentifier: Int,
        windowIdentifier: Int,
        excludingProcessIdentifier excludedPID: Int = Int(ProcessInfo.processInfo.processIdentifier)
    ) -> WindowInfo? {
        visibleWindows(excludingProcessIdentifier: excludedPID).first {
            $0.ownerProcessIdentifier == ownerProcessIdentifier
                && $0.windowIdentifier == windowIdentifier
        }
    }

    public static func appKitFrame(for window: WindowInfo, screen: ScreenInfo? = nil) -> CGRect? {
        guard let screen = screen ?? screenInfo(forWindowBounds: window.bounds) else { return nil }
        return appKitFrame(forWindowBounds: window.bounds, screen: screen)
    }

    private static func activeWindow(excludingProcessIdentifier excludedPID: Int) -> WindowInfo? {
        visibleWindows(excludingProcessIdentifier: excludedPID).first
    }

    private static func visibleWindows(excludingProcessIdentifier excludedPID: Int) -> [WindowInfo] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windows.compactMap { window -> WindowInfo? in
            guard intValue(window[kCGWindowLayer as String]) == 0 else { return nil }
            guard doubleValue(window[kCGWindowAlpha as String]) > 0 else { return nil }
            guard let ownerPID = intValue(window[kCGWindowOwnerPID as String]),
                  ownerPID != excludedPID else { return nil }
            guard let ownerName = clean(window[kCGWindowOwnerName as String] as? String),
                  ownerName != "Sidekick",
                  ownerName != "SidekickMCP" else { return nil }
            guard let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 40,
                  bounds.height >= 40 else { return nil }
            let windowID = intValue(window[kCGWindowNumber as String]) ?? 0
            let title = clean(window[kCGWindowName as String] as? String)
            return WindowInfo(
                title: title,
                ownerName: ownerName,
                ownerProcessIdentifier: ownerPID,
                windowIdentifier: windowID,
                bounds: bounds
            )
        }
    }

    private static func appInfo(for window: WindowInfo?) -> AppInfo? {
        guard let window,
              let app = NSRunningApplication(processIdentifier: pid_t(window.ownerProcessIdentifier)) else {
            return nil
        }
        return AppInfo(
            name: clean(app.localizedName) ?? window.ownerName,
            bundleIdentifier: clean(app.bundleIdentifier),
            processIdentifier: Int(app.processIdentifier)
        )
    }

    private static func fallbackFrontmostApp(excludingProcessIdentifier excludedPID: Int) -> AppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              Int(app.processIdentifier) != excludedPID else {
            return nil
        }
        return AppInfo(
            name: clean(app.localizedName) ?? "unknown",
            bundleIdentifier: clean(app.bundleIdentifier),
            processIdentifier: Int(app.processIdentifier)
        )
    }

    private static func screenInfo(forWindowBounds bounds: CGRect, screens: [NSScreen] = NSScreen.screens) -> ScreenInfo? {
        let candidates = screens.enumerated().compactMap { index, screen -> (info: ScreenInfo, area: CGFloat)? in
            guard let displayID = displayID(for: screen) else { return nil }
            let displayBounds = CGDisplayBounds(displayID)
            let intersection = bounds.intersection(displayBounds)
            guard intersection.isNull == false else {
                return (ScreenInfo(index: index, appKitFrame: screen.frame, displayBounds: displayBounds, displayIdentifier: displayID), 0)
            }
            let area = max(0, intersection.width) * max(0, intersection.height)
            return (ScreenInfo(index: index, appKitFrame: screen.frame, displayBounds: displayBounds, displayIdentifier: displayID), area)
        }
        guard let best = candidates.max(by: { $0.area < $1.area }) else { return nil }
        return best.area > 0 ? best.info : nil
    }

    private static func appKitFrame(forWindowBounds bounds: CGRect, screen: ScreenInfo) -> CGRect {
        let display = screen.displayBounds
        let appKit = screen.appKitFrame
        let x = appKit.minX + (bounds.minX - display.minX)
        let y = appKit.maxY - (bounds.maxY - display.minY)
        return CGRect(x: x, y: y, width: bounds.width, height: bounds.height)
    }

    private static func browserInfo(forBundleIdentifier bundleIdentifier: String?) -> BrowserInfo? {
        guard let script = browserScript(forBundleIdentifier: bundleIdentifier),
              let result = runBrowserScript(script) else {
            return nil
        }
        let parts = result.components(separatedBy: browserResultSeparator)
        let title = parts.indices.contains(0) ? clean(parts[0]) : nil
        let url = parts.indices.contains(1) ? clean(parts[1]) : nil
        guard title != nil || url != nil else { return nil }
        return BrowserInfo(title: title, url: url)
    }

    private static func browserScript(forBundleIdentifier bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else { return nil }
        switch bundleIdentifier {
        case "com.apple.Safari":
            return """
            with timeout of 1 seconds
                tell application id "com.apple.Safari"
                    if not (exists front document) then return ""
                    set activeTitle to name of front document
                    set activeURL to URL of front document
                    return activeTitle & "\(browserResultSeparator)" & activeURL
                end tell
            end timeout
            """
        case "com.google.Chrome",
             "com.google.Chrome.canary",
             "com.microsoft.edgemac",
             "com.brave.Browser",
             "company.thebrowser.Browser":
            return """
            with timeout of 1 seconds
                tell application id "\(bundleIdentifier)"
                    if (count of windows) = 0 then return ""
                    set activeTitle to title of active tab of front window
                    set activeURL to URL of active tab of front window
                    return activeTitle & "\(browserResultSeparator)" & activeURL
                end tell
            end timeout
            """
        default:
            return nil
        }
    }

    private static func runBrowserScript(_ script: String) -> String? {
        if Thread.isMainThread, let result = runAppleScript(script) {
            return result
        }
        return runOsaScript(script)
    }

    private static func runAppleScript(_ script: String) -> String? {
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error).stringValue
            if error == nil, let result {
                return result
            }
        }
        return nil
    }

    private static func runOsaScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    private static let browserResultSeparator = "|||SIDEKICK_BROWSER_URL|||"

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        return 1
    }

    private static func clean(_ value: String?, limit: Int = 500) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return nil }
        if cleaned.count <= limit { return cleaned }
        return String(cleaned.prefix(limit)) + "..."
    }

    private func quoted(_ value: String?) -> String {
        guard let value else { return "unknown" }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func format(_ rect: CGRect) -> String {
        "x=\(Int(rect.origin.x)) y=\(Int(rect.origin.y)) w=\(Int(rect.width)) h=\(Int(rect.height))"
    }
}
