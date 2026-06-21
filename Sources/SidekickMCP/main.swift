import Foundation

struct JSONRPCResponse: Encodable {
    let jsonrpc = "2.0"
    let id: JSONValue?
    let result: JSONValue?
    let error: JSONValue?
}

enum JSONValue: Encodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(_ value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(value.map(JSONValue.init))
        case let value as [String: Any]:
            self = .object(value.mapValues(JSONValue.init))
        default:
            self = .string(String(describing: value!))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            if value.rounded() == value {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
        }
    }
}

enum SidekickAnnotationMCP {
    static func run() {
        while let line = readLine() {
            guard let request = decode(line) else { continue }
            handle(request)
        }
    }

    private static func handle(_ request: [String: Any]) {
        guard let method = request["method"] as? String else { return }
        let id = JSONValue(request["id"])

        switch method {
        case "initialize":
            send(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "sidekick-annotation", "version": "0.1.0"],
            ])
        case "notifications/initialized", "initialized":
            return
        case "tools/list":
            send(id: id, result: ["tools": tools])
        case "tools/call":
            callTool(id: id, params: request["params"] as? [String: Any] ?? [:])
        default:
            sendError(id: id, code: -32601, message: "Unknown method \(method).")
        }
    }

    private static func callTool(id: JSONValue, params: [String: Any]) {
        guard let name = params["name"] as? String else {
            sendError(id: id, code: -32602, message: "Missing tool name.")
            return
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        do {
            switch name {
            case "annotate":
                let command = try annotationCommand(from: arguments)
                try appendCommand(command)
                sendToolText(id: id, "Queued Sidekick annotation.")
            case "clear_annotations":
                try appendCommand("clearground")
                sendToolText(id: id, "Cleared Sidekick annotations.")
            default:
                sendError(id: id, code: -32602, message: "Unknown tool \(name).")
            }
        } catch {
            sendToolText(id: id, error.localizedDescription, isError: true)
        }
    }

    private static func annotationCommand(from arguments: [String: Any]) throws -> String {
        guard let rawMarks = arguments["marks"] as? [[String: Any]], !rawMarks.isEmpty else {
            throw ToolError("annotate requires at least one mark.")
        }
        let message = (arguments["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tags = try rawMarks.map(tag(from:)).joined(separator: " ")
        return "ground:\(message.isEmpty ? "" : "\(message) ")\(tags)"
    }

    private static func tag(from mark: [String: Any]) throws -> String {
        guard let type = mark["type"] as? String else {
            throw ToolError("Each mark requires a type.")
        }
        let label = sanitize(mark["label"] as? String ?? "")
        let screenSuffix = (mark["screen"] as? Int).map { ":screen\($0)" } ?? ""
        switch type {
        case "point":
            return "[POINT:\(number(mark, "x")),\(number(mark, "y")):\(label)\(screenSuffix)]"
        case "target", "hover", "highlight":
            let upper = type.uppercased()
            return "[\(upper):\(number(mark, "x")),\(number(mark, "y")),\(number(mark, "radius")):\(label)\(screenSuffix)]"
        case "shape":
            let shape = (mark["shape"] as? String ?? "line").lowercased()
            guard ["line", "arrow", "circle", "curve", "polygon"].contains(shape) else {
                throw ToolError("Unsupported shape \(shape).")
            }
            guard let points = mark["points"] as? [[String: Any]], !points.isEmpty else {
                throw ToolError("Shape marks require points.")
            }
            let encoded = points.map { "\(number($0, "x")),\(number($0, "y"))" }.joined(separator: ";")
            return "[SHAPE:\(shape):\(encoded):\(label)\(screenSuffix)]"
        default:
            throw ToolError("Unsupported annotation type \(type).")
        }
    }

    private static func number(_ object: [String: Any], _ key: String) -> String {
        let value: Double
        if let double = object[key] as? Double {
            value = double
        } else if let int = object[key] as? Int {
            value = Double(int)
        } else if let number = object[key] as? NSNumber {
            value = number.doubleValue
        } else {
            value = 0
        }
        return value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendCommand(_ command: String) throws {
        let env = ProcessInfo.processInfo.environment
        let path = env["SIDEKICK_CMD_FILE"] ?? env["CLIPPY_CMD_FILE"] ?? defaultCommandFilePath()
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((command + "\n").utf8))
        try handle.close()
    }

    private static func defaultCommandFilePath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Sidekick", isDirectory: true).appendingPathComponent("cmd.txt").path
    }

    private static func sendToolText(id: JSONValue, _ text: String, isError: Bool = false) {
        send(id: id, result: [
            "content": [["type": "text", "text": text]],
            "isError": isError,
        ])
    }

    private static func send(id: JSONValue, result: [String: Any]) {
        write(JSONRPCResponse(id: id, result: JSONValue(result), error: nil))
    }

    private static func sendError(id: JSONValue, code: Int, message: String) {
        write(JSONRPCResponse(id: id, result: nil, error: JSONValue([
            "code": code,
            "message": message,
        ])))
    }

    private static func write(_ response: JSONRPCResponse) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(response),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
        fflush(stdout)
    }

    private static func decode(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static let tools: [[String: Any]] = [
        [
            "name": "annotate",
            "description": "Draw Sidekick-owned teaching annotations: point, target ring, hover ring, highlight, or shape path. Coordinates are pixels in the current Sidekick screenshot, top-left origin. Use this for explanations, highlights, arrows, regions, and multi-mark teaching. Use line/polygon shape marks for visible constructions; polygon shapes are closed outlines. Sidekick's body is the visible pointer; do not rely on a separate cursor overlay.",
            "inputSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "message": ["type": "string", "description": "Optional speech-bubble text to show with the annotation."],
                    "marks": [
                        "type": "array",
                        "minItems": 1,
                        "items": [
                            "type": "object",
                            "additionalProperties": true,
                            "properties": [
                                "type": ["type": "string", "enum": ["point", "target", "hover", "highlight", "shape"]],
                                "x": ["type": "number"],
                                "y": ["type": "number"],
                                "radius": ["type": "number"],
                                "label": ["type": "string"],
                                "screen": ["type": "integer"],
                                "shape": ["type": "string", "enum": ["line", "arrow", "circle", "curve", "polygon"]],
                                "points": [
                                    "type": "array",
                                    "items": [
                                        "type": "object",
                                        "properties": [
                                            "x": ["type": "number"],
                                            "y": ["type": "number"],
                                        ],
                                        "required": ["x", "y"],
                                    ],
                                ],
                            ],
                            "required": ["type"],
                        ],
                    ],
                ],
                "required": ["marks"],
            ],
        ],
        [
            "name": "clear_annotations",
            "description": "Clear Sidekick's annotation overlay.",
            "inputSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": [:],
            ],
        ],
    ]
}

struct ToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

SidekickAnnotationMCP.run()
