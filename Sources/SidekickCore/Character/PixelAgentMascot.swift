import AppKit

public enum PixelAgentMascotKind: String, CaseIterable, Equatable, Sendable {
    case claudeCode = "claude-code"
    case codex

    public init?(selection: String) {
        let normalized = selection.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "claude", "claude-code", "claudecode":
            self = .claudeCode
        case "codex", "codex-cli":
            self = .codex
        default:
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }

    public var theme: MascotTheme {
        switch self {
        case .claudeCode:
            return .claudeCode
        case .codex:
            return .codex
        }
    }

    public var style: PixelSidekickStyle {
        switch self {
        case .claudeCode:
            return .claudeCode
        case .codex:
            return .codex
        }
    }
}

@MainActor
public final class PixelAgentMascot: DesktopMascot {
    public let id: String
    public let displayName: String
    public let theme: MascotTheme
    public let renderer: PixelSidekickRenderer
    public let windowController: MascotWindowController
    public let idleAnimationNames = ["Idle", "IdleLook", "IdleRead", "IdleBlink"]
    public let gestureAnimationNames: [String]
    public private(set) var currentAnimationName: String?
    public var isMuted = false

    public init(kind: PixelAgentMascotKind) {
        self.id = kind.rawValue
        self.displayName = kind.displayName
        self.theme = kind.theme
        self.renderer = PixelSidekickRenderer(style: kind.style)
        self.gestureAnimationNames = [
            kind.theme.openInputAnimationName,
            kind.theme.replyAnimationName,
            kind.theme.fallbackGestureAnimationName,
            kind.theme.errorAnimationName,
        ]
        self.windowController = MascotWindowController(
            rendererLayer: renderer.rootLayer,
            size: renderer.bounds.size
        ) { [renderer] point in
            renderer.containsVisiblePoint(point)
        }
    }

    @discardableResult
    public func play(_ animationName: String, onEnd: ((String, MascotAnimationEndState) -> Void)? = nil) -> Bool {
        currentAnimationName = animationName
        renderer.show(animationName)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else {
                return
            }
            onEnd?(animationName, .exited)
            if self.currentAnimationName == animationName {
                self.currentAnimationName = nil
            }
        }
        return true
    }

    public func exitCurrentAnimation() {
        currentAnimationName = nil
    }

    public func snapshotPNGData() -> Data? {
        renderer.snapshotPNGData()
    }
}
