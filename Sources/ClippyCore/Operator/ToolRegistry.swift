import Foundation

public enum ToolApproval: String, Codable, Equatable, Sendable {
    case notRequired
    case required
}

public struct ClippyTool: Sendable {
    public let name: String
    public let description: String
    public let approval: ToolApproval

    public init(name: String, description: String, approval: ToolApproval) {
        self.name = name
        self.description = description
        self.approval = approval
    }
}

public enum ToolRegistry {
    public static let recommended: [ClippyTool] = [
        ClippyTool(name: "character.show", description: "Show the desktop character.", approval: .notRequired),
        ClippyTool(name: "character.play", description: "Play a named character animation.", approval: .notRequired),
        ClippyTool(name: "character.say", description: "Show or speak an assistant response.", approval: .notRequired),
        ClippyTool(name: "character.move_to", description: "Move the character to a screen point.", approval: .notRequired),
        ClippyTool(name: "character.point_at", description: "Gesture toward a target rectangle or point.", approval: .notRequired),
        ClippyTool(name: "observe.screen", description: "Capture the Mac screen for visual context.", approval: .notRequired),
        ClippyTool(name: "observe.ui_tree", description: "Inspect focused app or element UI metadata.", approval: .notRequired),
        ClippyTool(name: "observe.camera", description: "Capture one camera frame after explicit user intent.", approval: .required),
        ClippyTool(name: "computer.check_permissions", description: "Check Accessibility and Screen Recording state.", approval: .notRequired),
        ClippyTool(name: "computer.launch_app", description: "Open an app, file, or URL using a background-safe launcher.", approval: .notRequired),
        ClippyTool(name: "computer.list_windows", description: "List visible target windows.", approval: .notRequired),
        ClippyTool(name: "computer.get_window_state", description: "Capture a window accessibility tree plus screenshot.", approval: .notRequired),
        ClippyTool(name: "computer.click_element", description: "Click an element from the latest window snapshot.", approval: .required),
        ClippyTool(name: "computer.set_value", description: "Set an element value from the latest window snapshot.", approval: .required),
        ClippyTool(name: "computer.type_text", description: "Type text into a target window.", approval: .required),
        ClippyTool(name: "computer.press_key", description: "Press a key in a target window.", approval: .required),
        ClippyTool(name: "computer.scroll", description: "Scroll a target window.", approval: .required),
        ClippyTool(name: "computer.screenshot", description: "Capture a diagnostic screenshot.", approval: .notRequired),
        ClippyTool(name: "shell.exec", description: "Run a simple local shell command.", approval: .required),
        ClippyTool(name: "request_approval", description: "Ask for approval before sensitive work.", approval: .notRequired),
    ]
}
