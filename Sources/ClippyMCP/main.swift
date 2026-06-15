import Foundation

// Minimal MCP (Model Context Protocol) stdio server exposing Clippy's behavior as
// REAL tools the model can call (clippy_act, clippy_point, clippy_highlight). Tool
// calls are relayed to the running Clippy app through its command file — the same
// channel the debug commands use — so a `claude --mcp-config` / codex subprocess can
// drive the live mascot. This is the "real tool calling" layer (vs the inline tags
// used for streamed cosmetic signals); see Docs/STATUS for the architecture.

private let commandFilePath: String = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    let directory = base.appendingPathComponent("Clippy", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("cmd.txt").path
}()

private func appendCommand(_ line: String) {
    let data = Data((line + "\n").utf8)
    if let handle = FileHandle(forWritingAtPath: commandFilePath) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        FileManager.default.createFile(atPath: commandFilePath, contents: data)
    }
}

private func reply(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
}

private func result(id: Any?, _ value: [String: Any]) {
    reply(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": value])
}

private func toDouble(_ any: Any?) -> Double? {
    if let d = any as? Double { return d }
    if let i = any as? Int { return Double(i) }
    if let s = any as? String { return Double(s) }
    return nil
}

private let tools: [[String: Any]] = [
    [
        "name": "clippy_act",
        "description": "Make Clippy perform an animation to express what it is doing or feeling. Examples: Wave, Congratulate, GetAttention, Explain, GetArtsy, GetTechy, GetWizardy, Searching, Processing, Writing, Alert, IdleHeadScratch, IdleEyeBrowRaise.",
        "inputSchema": [
            "type": "object",
            "properties": ["animation": ["type": "string", "description": "Exact animation name from Clippy's character pack."]],
            "required": ["animation"],
        ],
    ],
    [
        "name": "clippy_point",
        "description": "Move Clippy to a screen coordinate and point at it with its body, showing a label.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "x": ["type": "number", "description": "X in screen pixels."],
                "y": ["type": "number", "description": "Y in screen pixels."],
                "label": ["type": "string", "description": "Short label for what is being pointed at."],
            ],
            "required": ["x", "y"],
        ],
    ],
    [
        "name": "clippy_highlight",
        "description": "Outline a region of the screen for the user (a work area).",
        "inputSchema": [
            "type": "object",
            "properties": [
                "x": ["type": "number"], "y": ["type": "number"],
                "radius": ["type": "number"], "label": ["type": "string"],
            ],
            "required": ["x", "y", "radius"],
        ],
    ],
]

private func handleToolCall(_ params: [String: Any]?) -> String {
    let name = params?["name"] as? String
    let args = params?["arguments"] as? [String: Any] ?? [:]
    switch name {
    case "clippy_act":
        guard let animation = args["animation"] as? String, !animation.isEmpty else { return "Missing animation name." }
        appendCommand("act:\(animation)")
        return "Clippy is performing \(animation)."
    case "clippy_point":
        guard let x = toDouble(args["x"]), let y = toDouble(args["y"]) else { return "Missing x/y." }
        let label = (args["label"] as? String) ?? "here"
        appendCommand("ground:[POINT:\(Int(x)),\(Int(y)):\(label)]")
        return "Clippy is pointing at \(Int(x)),\(Int(y))."
    case "clippy_highlight":
        guard let x = toDouble(args["x"]), let y = toDouble(args["y"]), let r = toDouble(args["radius"]) else { return "Missing x/y/radius." }
        let label = (args["label"] as? String) ?? "this area"
        appendCommand("ground:[HIGHLIGHT:\(Int(x)),\(Int(y)),\(Int(r)):\(label)]")
        return "Clippy highlighted \(Int(x)),\(Int(y))."
    default:
        return "Unknown tool."
    }
}

// MARK: - Stdio JSON-RPC loop (newline-delimited messages)

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty,
          let data = line.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
    let method = message["method"] as? String
    let id = message["id"]
    switch method {
    case "initialize":
        result(id: id, [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "clippy", "version": "0.1.0"],
        ])
    case "notifications/initialized", "notifications/cancelled":
        break
    case "tools/list":
        result(id: id, ["tools": tools])
    case "tools/call":
        let text = handleToolCall(message["params"] as? [String: Any])
        result(id: id, ["content": [["type": "text", "text": text]]])
    case "ping":
        result(id: id, [:])
    default:
        if id != nil {
            reply(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": -32601, "message": "Method not found"]])
        }
    }
}
