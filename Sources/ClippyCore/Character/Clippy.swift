import AppKit
import SpriteKit

public enum ClippyAnimationEndState: Equatable, Sendable {
    case waiting
    case exited
}

public enum ClippyParkEdge: String, Equatable, Sendable {
    case lowerLeft
    case lowerRight
    case upperLeft
    case upperRight
}

@MainActor
public final class Clippy {
    public let id = "clippy"
    public let displayName = "Clippy"
    public let spec = ClippySpec.current
    public let windowController: ClippyWindowController
    public let renderer: SpriteKitRasterCharacterRenderer
    public let animator: ClippyAnimator
    public let soundBank: ClippySoundBank?
    public private(set) var bodyScale: ClippyBodyScale

    private let sheet: ClippySpriteSheet

    private static let idleAnimationNamesList = [
        "Idle1_1", "IdleAtom", "IdleEyeBrowRaise", "IdleFingerTap",
        "IdleHeadScratch", "IdleRopePile", "IdleSideToSide", "IdleSnooze",
        "LookLeft", "LookRight",
    ]
    private static let gestureAnimationNamesList = [
        "Congratulate", "GetAttention", "Wave", "Print", "Save", "GetArtsy",
        "GetTechy", "GetWizardy", "Explain", "Alert", "CheckingSomething",
        "EmptyTrash", "SendMail", "Writing", "Processing",
    ]
    public let idleAnimationNames = Clippy.idleAnimationNamesList
    public let gestureAnimationNames = Clippy.gestureAnimationNamesList

    public convenience init(packRoot: URL, scale: CGFloat = ClippyBodyScale.default.rasterScale) throws {
        try self.init(packRoot: packRoot, bodyScale: ClippyBodyScale(Double(scale / ClippyBodyScale.defaultRasterScale)))
    }

    public init(packRoot: URL, bodyScale: ClippyBodyScale = .default) throws {
        let sheet = try ClippySpriteSheet(packRoot: packRoot)
        sheet.preloadTextures(for: Self.preloadedAnimationNames)
        let size = Self.windowSize(frameSize: sheet.frameSize, bodyScale: bodyScale)
        let renderer = SpriteKitRasterCharacterRenderer(size: size)
        let animator = ClippyAnimator(sheet: sheet, renderer: renderer)
        let soundBank = try? ClippySoundBank(packRoot: packRoot)
        animator.soundBank = soundBank

        self.sheet = sheet
        self.renderer = renderer
        self.animator = animator
        self.soundBank = soundBank
        self.bodyScale = bodyScale
        self.windowController = ClippyWindowController(rendererView: renderer.view, size: size) { point in
            point.x >= 0 && point.y >= 0
        }
    }

    private static var preloadedAnimationNames: [String] {
        let spec = ClippySpec.current
        let stateAnimations = AgentActivityState.allCases.compactMap { spec.animation(for: $0)?.animationName }
        return Array(Set(
            stateAnimations
            + [
                "RestPose",
                "GestureLeft",
                "GestureRight",
                "GestureUp",
                "GestureDown",
                spec.greetingAnimationName,
                spec.openInputAnimationName,
                spec.replyAnimationName,
                spec.errorAnimationName,
                spec.fallbackGestureAnimationName,
            ]
        ))
    }

    public var frame: CGRect {
        windowController.frame
    }

    public var currentAnimationName: String? {
        animator.currentAnimationName
    }

    public var isMuted: Bool {
        get { soundBank?.isMuted ?? false }
        set { soundBank?.isMuted = newValue }
    }

    public func show() {
        windowController.show()
    }

    public func move(to origin: CGPoint, animated: Bool = true) {
        windowController.move(to: origin, animated: animated)
    }

    public func resizeBody(to bodyScale: ClippyBodyScale, in visibleFrame: CGRect? = nil, animated: Bool = true) {
        let size = Self.windowSize(frameSize: sheet.frameSize, bodyScale: bodyScale)
        let oldFrame = windowController.frame
        var origin = CGPoint(x: oldFrame.midX - size.width / 2, y: oldFrame.minY)
        if let visibleFrame {
            origin = Self.clampedOrigin(origin, size: size, in: visibleFrame)
        }
        self.bodyScale = bodyScale
        renderer.resize(to: size)
        windowController.resize(to: size, anchoredAt: origin, animated: animated) { [renderer] in
            renderer.resize(to: size)
        }
    }

    public func park(in visibleFrame: CGRect, edge: ClippyParkEdge) {
        let size = windowController.frame.size
        let margin: CGFloat = 24
        let origin: CGPoint
        switch edge {
        case .lowerLeft:
            origin = CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.minY + margin)
        case .lowerRight:
            origin = CGPoint(x: visibleFrame.maxX - size.width - margin, y: visibleFrame.minY + margin)
        case .upperLeft:
            origin = CGPoint(x: visibleFrame.minX + margin, y: visibleFrame.maxY - size.height - margin)
        case .upperRight:
            origin = CGPoint(x: visibleFrame.maxX - size.width - margin, y: visibleFrame.maxY - size.height - margin)
        }
        move(to: origin, animated: true)
    }

    public func point(at rect: CGRect) {
        let targetX = rect.midX
        let targetY = rect.midY
        let current = frame
        let dx = targetX - current.midX
        let dy = targetY - current.midY
        let animation: String
        if abs(dx) > abs(dy) {
            animation = dx < 0 ? "LookLeft" : "LookRight"
        } else {
            animation = dy > 0 ? "Explain" : "GetAttention"
        }
        _ = play(animation, onEnd: nil)
    }

    @discardableResult
    public func play(_ animationName: String, onEnd: ((String, ClippyAnimationEndState) -> Void)? = nil) -> Bool {
        animator.play(animationName) { name, endState in
            let mapped: ClippyAnimationEndState = endState == .waiting ? .waiting : .exited
            onEnd?(name, mapped)
        }
    }

    public func exitCurrentAnimation() {
        animator.exitCurrentAnimation()
    }

    public func snapshotPNGData() -> Data? {
        guard
            let scene = renderer.view.scene,
            let texture = renderer.view.texture(from: scene)
        else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: texture.cgImage())
        return rep.representation(using: .png, properties: [:])
    }

    private static func windowSize(frameSize: CGSize, bodyScale: ClippyBodyScale) -> CGSize {
        CGSize(
            width: (frameSize.width * bodyScale.rasterScale).rounded(),
            height: (frameSize.height * bodyScale.rasterScale).rounded()
        )
    }

    private static func clampedOrigin(_ origin: CGPoint, size: CGSize, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
    }
}
