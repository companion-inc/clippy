import Foundation

public struct SidecarProcessConfiguration: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?

    public init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

public enum SidecarStatus: Equatable, Sendable {
    case stopped
    case running(pid: Int32)
}

public enum SidecarProcessError: Error, Equatable {
    case alreadyRunning
    case launchFailed(String)
}

public actor SidecarProcessSupervisor {
    private var process: Process?

    public init() {}

    public var status: SidecarStatus {
        guard let process, process.isRunning else {
            return .stopped
        }
        return .running(pid: process.processIdentifier)
    }

    public func start(_ configuration: SidecarProcessConfiguration) throws {
        if case .running = status {
            throw SidecarProcessError.alreadyRunning
        }

        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment) { _, new in new }
        process.currentDirectoryURL = configuration.workingDirectory

        do {
            try process.run()
            self.process = process
        } catch {
            throw SidecarProcessError.launchFailed(error.localizedDescription)
        }
    }

    public func stop() {
        guard let process else {
            return
        }
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
    }
}
