import Foundation

public enum MicrophoneTapOwner: String, Equatable, Sendable {
    case wakeWord
    case deepgramSTT
    case appleSpeech
}

public enum MicrophoneTapCoordinatorError: Error, Equatable, CustomStringConvertible {
    case alreadyOwned(MicrophoneTapOwner)

    public var description: String {
        switch self {
        case .alreadyOwned(let owner):
            "microphone tap already owned by \(owner.rawValue)"
        }
    }
}

public final class MicrophoneTapCoordinator {
    public static let shared = MicrophoneTapCoordinator()

    private let lock = NSLock()
    private var owner: MicrophoneTapOwner?

    public init() {}

    public var currentOwner: MicrophoneTapOwner? {
        lock.lock()
        defer { lock.unlock() }
        return owner
    }

    public func acquire(_ requestedOwner: MicrophoneTapOwner) throws {
        lock.lock()
        defer { lock.unlock() }

        if let owner {
            throw MicrophoneTapCoordinatorError.alreadyOwned(owner)
        }
        owner = requestedOwner
    }

    public func release(_ releasedOwner: MicrophoneTapOwner) {
        lock.lock()
        defer { lock.unlock() }

        guard owner == releasedOwner else { return }
        owner = nil
    }
}
