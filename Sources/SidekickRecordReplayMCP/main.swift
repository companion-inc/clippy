import SidekickCore
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
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            if value.rounded() == value {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case .string(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        case .object(let values):
            try container.encode(values)
        }
    }
}

enum SidekickRecordReplayMCP {
    private static let recorder = SidekickChronicleRecorder.shared

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
                "serverInfo": ["name": "sidekick-record-replay", "version": "0.1.0"],
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

        do {
            switch name {
            case "event_stream_start":
                let metadata = try recorder.start()
                sendMetadata(id: id, metadata: metadata, prefix: "Started Sidekick recording.")
            case "event_stream_status":
                if let metadata = try recorder.status() {
                    sendMetadata(id: id, metadata: metadata, prefix: "Sidekick recording status: \(metadata.state.rawValue).")
                } else {
                    send(id: id, result: [
                        "content": [[
                            "type": "text",
                            "text": "No Sidekick recording has been started in this session.",
                        ]],
                        "structuredContent": [
                            "state": ChronicleRecordingState.idle.rawValue,
                            "storageRoot": SidekickChronicleRecorder.defaultStorageRoot.path,
                        ],
                        "isError": false,
                    ])
                }
            case "event_stream_stop":
                let metadata = try recorder.stop()
                sendMetadata(id: id, metadata: metadata, prefix: "Stopped Sidekick recording.")
            default:
                sendError(id: id, code: -32602, message: "Unknown tool \(name).")
            }
        } catch {
            sendToolText(id: id, error.localizedDescription, isError: true)
        }
    }

    private static func sendMetadata(id: JSONValue, metadata: ChronicleSessionMetadata, prefix: String) {
        let object = metadataJSONObject(metadata)
        let text = """
        \(prefix)
        metadataPath: \(metadata.metadataPath)
        eventsPath: \(metadata.eventsPath)
        framesDirectory: \(metadata.framesDirectory)
        state: \(metadata.state.rawValue)
        eventCount: \(metadata.eventCount)
        frameCount: \(metadata.frameCount)
        """
        send(id: id, result: [
            "content": [["type": "text", "text": text]],
            "structuredContent": object,
            "isError": false,
        ])
    }

    private static func metadataJSONObject(_ metadata: ChronicleSessionMetadata) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(metadata),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [
                "id": metadata.id,
                "state": metadata.state.rawValue,
                "metadataPath": metadata.metadataPath,
                "eventsPath": metadata.eventsPath,
                "framesDirectory": metadata.framesDirectory,
            ]
        }
        return object
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
            "name": "event_stream_start",
            "description": "Start recording the user's Sidekick workflow for up to 30 minutes. Returns the active session if one is already recording.",
            "annotations": [
                "destructiveHint": false,
                "idempotentHint": false,
                "openWorldHint": false,
                "readOnlyHint": false,
            ],
            "inputSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": [:],
            ],
        ],
        [
            "name": "event_stream_status",
            "description": "Get the current or most recent Sidekick recording status, including paths to session metadata and event files.",
            "annotations": [
                "destructiveHint": false,
                "idempotentHint": true,
                "openWorldHint": false,
                "readOnlyHint": true,
            ],
            "inputSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": [:],
            ],
        ],
        [
            "name": "event_stream_stop",
            "description": "Stop the active Sidekick recording and return paths to the metadata and event stream.",
            "annotations": [
                "destructiveHint": false,
                "idempotentHint": true,
                "openWorldHint": false,
                "readOnlyHint": false,
            ],
            "inputSchema": [
                "type": "object",
                "additionalProperties": false,
                "properties": [:],
            ],
        ],
    ]
}

SidekickRecordReplayMCP.run()
