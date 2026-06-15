import ApplicationServices
import Foundation

public enum AccessibilityPermission {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestIfNeeded(prompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
