import Foundation

/// Clippy's Codex brain uses the same app-server surface that rich Codex
/// clients use. `codex exec --json` is noninteractive automation output; the
/// app-server protocol is where Codex emits real `item/agentMessage/delta`
/// chunks while one thread stays alive across Clippy turns.
public actor CodexConversation: AgentBrain {
    private let binaryPath: String
    private let model: String
    private let effort: String
    private let workingDirectory: String?
    private let systemPrompt: String?
    private var appServer: AppServerConnection?
    private var threadID: String?
    private var nextRequestID = 0

    public init(
        binaryPath: String,
        model: String = "gpt-5.5",
        // "low" is the floor that works: `minimal` 400s because GPT-5.5's default
        // image_gen/web_search tools can't be used with minimal reasoning effort.
        effort: String = "low",
        workingDirectory: String? = nil,
        systemPrompt: String? = ClippyAgentInstructions.systemPrompt
    ) {
        self.binaryPath = binaryPath
        self.model = model
        self.effort = effort
        self.workingDirectory = workingDirectory
        self.systemPrompt = systemPrompt
    }

    deinit {
        appServer?.terminate()
    }

    public static func locateBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/bin/zsh")
        probe.arguments = ["-lc", "command -v codex"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        try? probe.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        probe.waitUntilExit()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    public func send(_ message: String) async -> AgentTurn {
        var partial = ""
        for await chunk in stream(message) {
            switch chunk {
            case .partial(let text):
                partial = text
            case .final(let turn):
                return turn
            }
        }
        if !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AgentTurn(text: partial.trimmingCharacters(in: .whitespacesAndNewlines), isError: false)
        }
        return AgentTurn(text: "Codex returned nothing (model \(model)).", isError: true)
    }

    public nonisolated func stream(_ message: String) -> AsyncStream<AgentStreamChunk> {
        AsyncStream { continuation in
            let box = ProcessBox()
            let work = Task { await self.runStreaming(message, continuation: continuation, process: box) }
            continuation.onTermination = { @Sendable _ in
                work.cancel()
                box.terminate()
            }
        }
    }

    private func runStreaming(
        _ message: String,
        continuation: AsyncStream<AgentStreamChunk>.Continuation,
        process box: ProcessBox
    ) async {
        var accumulated = ""
        var finalText: String?
        var isError = false
        var finalError: String?

        do {
            let connection = try ensureAppServer(process: box)
            let activeThreadID = try ensureThread(on: connection)
            box.set(connection.process)
            defer {
                box.set(nil)
                if !connection.process.isRunning {
                    appServer = nil
                    threadID = nil
                }
            }

            let turnRequestID = try sendRequest(
                "turn/start",
                params: [
                    "threadId": activeThreadID,
                    "input": [
                        [
                            "type": "text",
                            "text": message,
                            "text_elements": [],
                        ],
                    ],
                    "cwd": jsonValue(workingDirectory),
                    "approvalPolicy": "never",
                    "approvalsReviewer": NSNull(),
                    "sandboxPolicy": ["type": "dangerFullAccess"],
                    "model": model,
                    "effort": effort,
                    "summary": "none",
                    "personality": "none",
                    "outputSchema": NSNull(),
                ],
                on: connection
            )

            var activeTurnID: String?
            var sawTurnCompletion = false

            while let line = try connection.readLine() {
                if Task.isCancelled { throw CancellationError() }
                guard let object = Self.decodeJSONObject(line) else { continue }

                if Self.messageID(object) == turnRequestID {
                    if let error = Self.errorMessage(from: object) {
                        throw AppServerError(error)
                    }
                    activeTurnID = Self.turnID(fromTurnStartResponse: object) ?? activeTurnID
                    continue
                }

                guard let method = object["method"] as? String else { continue }
                let params = object["params"] as? [String: Any]

                switch method {
                case "item/agentMessage/delta":
                    guard Self.threadID(from: params) == activeThreadID,
                          Self.turnID(from: params).map({ $0 == activeTurnID }) ?? true,
                          let delta = params?["delta"] as? String,
                          !delta.isEmpty
                    else { continue }
                    accumulated += delta
                    continuation.yield(.partial(accumulated))

                case "item/completed":
                    guard Self.threadID(from: params) == activeThreadID,
                          Self.turnID(from: params).map({ $0 == activeTurnID }) ?? true,
                          let item = params?["item"] as? [String: Any],
                          (item["type"] as? String) == "agentMessage",
                          let text = item["text"] as? String,
                          !text.isEmpty
                    else { continue }
                    finalText = text

                case "turn/completed":
                    guard Self.threadID(from: params) == activeThreadID else { continue }
                    if let turn = params?["turn"] as? [String: Any] {
                        let completedTurnID = turn["id"] as? String
                        if let activeTurnID, completedTurnID != activeTurnID { continue }
                        if let status = turn["status"] as? String, status == "failed" || status == "interrupted" {
                            isError = true
                        }
                        if let error = turn["error"] as? [String: Any],
                           let message = error["message"] as? String,
                           !message.isEmpty {
                            finalError = message
                        }
                    }
                    sawTurnCompletion = true

                case "error":
                    if Self.threadID(from: params) == activeThreadID,
                       Self.turnID(from: params).map({ $0 == activeTurnID }) ?? true {
                        isError = true
                        finalError = Self.errorMessage(fromNotificationParams: params)
                    }

                default:
                    break
                }

                if sawTurnCompletion { break }
            }

            if !sawTurnCompletion && !Task.isCancelled {
                isError = true
                finalError = "Codex app-server closed before the turn completed."
            }
        } catch is CancellationError {
            appServer = nil
            threadID = nil
            continuation.finish()
            return
        } catch {
            isError = true
            finalError = "I couldn't stream from Codex: \(error.localizedDescription)"
        }

        let text = (finalText?.isEmpty == false ? finalText! : accumulated)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            continuation.yield(.final(AgentTurn(
                text: finalError ?? "Codex returned nothing (model \(model)).",
                isError: true
            )))
        } else {
            continuation.yield(.final(AgentTurn(text: text, isError: isError)))
        }
        continuation.finish()
    }

    private func ensureAppServer(process box: ProcessBox) throws -> AppServerConnection {
        if let appServer, appServer.process.isRunning {
            box.set(appServer.process)
            return appServer
        }

        appServer?.terminate()
        appServer = nil
        threadID = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "app-server",
            "--stdio",
            "--disable", "apps",
            "-c", "model=\"\(model)\"",
            "-c", "model_reasoning_effort=\"\(effort)\"",
            "-c", "mcp_servers={}",
        ]
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        process.environment = ProcessInfo.processInfo.environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw AppServerError("Could not start codex app-server: \(error.localizedDescription)")
        }

        box.set(process)
        Task.detached(priority: .utility) {
            _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        }

        let connection = AppServerConnection(
            process: process,
            input: inputPipe.fileHandleForWriting,
            output: outputPipe.fileHandleForReading
        )
        appServer = connection

        let initializeID = try sendRequest(
            "initialize",
            params: [
                "clientInfo": [
                    "name": "clippy",
                    "title": "Clippy",
                    "version": "0.1.0",
                ],
                "capabilities": [
                    "experimentalApi": true,
                    "requestAttestation": false,
                    "optOutNotificationMethods": [],
                ],
            ],
            on: connection
        )
        _ = try readResponse(id: initializeID, on: connection)
        try sendNotification("initialized", on: connection)

        return connection
    }

    private func ensureThread(on connection: AppServerConnection) throws -> String {
        if let threadID, connection.process.isRunning {
            return threadID
        }

        let threadStartID = try sendRequest(
            "thread/start",
            params: [
                "model": model,
                "modelProvider": NSNull(),
                "cwd": jsonValue(workingDirectory),
                "approvalPolicy": "never",
                "approvalsReviewer": NSNull(),
                "sandbox": "danger-full-access",
                "config": [
                    "mcp_servers": [:],
                    "model_reasoning_effort": effort,
                    "features": ["apps": false],
                ],
                "serviceName": "clippy",
                "baseInstructions": NSNull(),
                "developerInstructions": jsonValue(systemPrompt),
                "personality": "none",
                "ephemeral": true,
                "sessionStartSource": "startup",
                "threadSource": "user",
            ],
            on: connection
        )
        let response = try readResponse(id: threadStartID, on: connection)
        guard let startedThreadID = Self.threadID(fromThreadStartResponse: response), !startedThreadID.isEmpty else {
            throw AppServerError("codex app-server did not return a thread id.")
        }
        threadID = startedThreadID
        return startedThreadID
    }

    private func sendRequest(
        _ method: String,
        params: [String: Any],
        on connection: AppServerConnection
    ) throws -> Int {
        nextRequestID += 1
        let id = nextRequestID
        try connection.send(["method": method, "id": id, "params": params])
        return id
    }

    private func sendNotification(_ method: String, on connection: AppServerConnection) throws {
        try connection.send(["method": method])
    }

    private func readResponse(id: Int, on connection: AppServerConnection) throws -> [String: Any] {
        while let line = try connection.readLine() {
            guard let object = Self.decodeJSONObject(line) else { continue }
            if let error = Self.errorMessage(from: object), Self.messageID(object) == id {
                throw AppServerError(error)
            }
            if Self.messageID(object) == id {
                return object
            }
        }
        throw AppServerError("codex app-server closed before response \(id).")
    }

    private func jsonValue(_ value: String?) -> Any {
        guard let value, !value.isEmpty else { return NSNull() }
        return value
    }

    private static func decodeJSONObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func messageID(_ object: [String: Any]) -> Int? {
        if let id = object["id"] as? Int { return id }
        if let id = object["id"] as? NSNumber { return id.intValue }
        if let id = object["id"] as? String { return Int(id) }
        return nil
    }

    private static func errorMessage(from object: [String: Any]) -> String? {
        guard let error = object["error"] as? [String: Any] else { return nil }
        if let message = error["message"] as? String { return message }
        return String(describing: error)
    }

    private static func errorMessage(fromNotificationParams params: [String: Any]?) -> String? {
        guard let error = params?["error"] as? [String: Any] else { return nil }
        if let message = error["message"] as? String { return message }
        return String(describing: error)
    }

    private static func threadID(from params: [String: Any]?) -> String? {
        params?["threadId"] as? String
    }

    private static func turnID(from params: [String: Any]?) -> String? {
        params?["turnId"] as? String
    }

    private static func threadID(fromThreadStartResponse object: [String: Any]) -> String? {
        guard let result = object["result"] as? [String: Any],
              let thread = result["thread"] as? [String: Any] else {
            return nil
        }
        return thread["id"] as? String
    }

    private static func turnID(fromTurnStartResponse object: [String: Any]) -> String? {
        guard let result = object["result"] as? [String: Any],
              let turn = result["turn"] as? [String: Any] else {
            return nil
        }
        return turn["id"] as? String
    }
}

private final class AppServerConnection {
    let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()

    init(process: Process, input: FileHandle, output: FileHandle) {
        self.process = process
        self.input = input
        self.output = output
    }

    func send(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        input.write(data)
        input.write(Data([0x0A]))
    }

    func readLine() throws -> String? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                return String(data: line, encoding: .utf8)
            }
            let chunk = output.readData(ofLength: 1)
            guard !chunk.isEmpty else {
                if buffer.isEmpty { return nil }
                let remainder = buffer
                buffer.removeAll()
                return String(data: remainder, encoding: .utf8)
            }
            buffer.append(chunk)
        }
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}

private struct AppServerError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
