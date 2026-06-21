import AppKit
import SpriteKit

public enum SidekickAnimationEndState: Equatable, Sendable {
    case waiting
    case exited
}

public enum SidekickParkEdge: String, Equatable, Sendable {
    case lowerLeft
    case lowerRight
    case upperLeft
    case upperRight
}

@MainActor
public final class SidekickCharacter {
    public let id: String
    public let displayName: String
    public let spec: SidekickSpec
    public let windowController: SidekickWindowController
    public let renderer: SpriteKitRasterCharacterRenderer
    public let animator: SidekickAnimator
    public let soundBank: SidekickSoundBank?
    public private(set) var bodyScale: SidekickBodyScale

    private let sheet: SidekickSpriteSheet

    private static let preferredIdleAnimationNames = [
        "Idle1_1", "IdleAtom", "IdleEyeBrowRaise", "IdleFingerTap",
        "IdleHeadScratch", "IdleRopePile", "IdleSideToSide", "IdleSnooze",
        "IdleBlink", "Idle", "LookLeft", "LookRight", "Blink",
    ]
    private static let preferredGestureAnimationNames = [
        "Congratulate", "GetAttention", "Wave", "Print", "Save", "GetArtsy",
        "GetTechy", "GetWizardy", "Explain", "Alert", "CheckingSomething",
        "EmptyTrash", "SendMail", "Writing", "Processing", "Acknowledge",
        "Announce", "Pleased", "Surprised", "Think",
    ]
    public let idleAnimationNames: [String]
    public let gestureAnimationNames: [String]

    public convenience init(packRoot: URL, spec: SidekickSpec = .current, scale: CGFloat = SidekickBodyScale.default.rasterScale) throws {
        try self.init(
            packRoot: packRoot,
            spec: spec,
            bodyScale: SidekickBodyScale(Double(scale / SidekickBodyScale.defaultRasterScale))
        )
    }

    public init(packRoot: URL, spec: SidekickSpec = .current, bodyScale: SidekickBodyScale = .default) throws {
        let sheet = try SidekickSpriteSheet(packRoot: packRoot)
        sheet.preloadTextures(for: Self.preloadedAnimationNames(spec: spec, availableAnimations: sheet.pack.animationNames))
        let size = Self.windowSize(frameSize: sheet.frameSize, bodyScale: bodyScale)
        let renderer = SpriteKitRasterCharacterRenderer(size: size)
        let animator = SidekickAnimator(sheet: sheet, renderer: renderer)
        let soundBank = try? SidekickSoundBank(packRoot: packRoot)
        animator.soundBank = soundBank
        try? renderer.show(
            animationName: Self.initialVisibleAnimationName(spec: spec, pack: sheet.pack),
            spriteSheet: sheet
        )

        self.id = spec.id
        self.displayName = spec.displayName
        self.spec = spec
        self.sheet = sheet
        self.renderer = renderer
        self.animator = animator
        self.soundBank = soundBank
        self.bodyScale = bodyScale
        self.idleAnimationNames = Self.preferredIdleAnimationNames.filter { sheet.pack.animations[$0] != nil }
        self.gestureAnimationNames = Self.preferredGestureAnimationNames.filter { sheet.pack.animations[$0] != nil }
        self.windowController = SidekickWindowController(rendererView: renderer.view, size: size) { point in
            point.x >= 0 && point.y >= 0
        }
    }

    private static func preloadedAnimationNames(spec: SidekickSpec, availableAnimations: [String]) -> [String] {
        let available = Set(availableAnimations)
        let stateAnimations = AgentActivityState.allCases
            .compactMap { spec.animation(for: $0)?.animationName }
            .filter { available.contains($0) }
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
            .filter { available.contains($0) }
        ))
    }

    private static func initialVisibleAnimationName(spec: SidekickSpec, pack: RasterCharacterPack) -> String {
        for candidate in [
            spec.greetingAnimationName,
            "Greet",
            "Greeting",
            "Show",
            spec.openInputAnimationName,
            spec.replyAnimationName,
            "RestPose",
        ] where pack.animations[candidate] != nil {
            return candidate
        }
        return pack.animationNames.first ?? spec.greetingAnimationName
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

    public func resizeBody(to bodyScale: SidekickBodyScale, in visibleFrame: CGRect? = nil, animated: Bool = true) {
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

    public func park(in visibleFrame: CGRect, edge: SidekickParkEdge) {
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
    public func play(_ animationName: String, onEnd: ((String, SidekickAnimationEndState) -> Void)? = nil) -> Bool {
        let resolvedAnimationName = resolveAnimationName(animationName)
        return animator.play(resolvedAnimationName) { name, endState in
            let mapped: SidekickAnimationEndState = endState == .waiting ? .waiting : .exited
            onEnd?(name, mapped)
        }
    }

    public func canPlay(_ animationName: String) -> Bool {
        sheet.pack.animations[animationName] != nil
    }

    public func resolveAnimationName(_ animationName: String) -> String {
        if canPlay(animationName) {
            return animationName
        }
        for fallback in [
            spec.fallbackGestureAnimationName,
            spec.replyAnimationName,
            "Explain",
            "GetAttention",
            "Acknowledge",
            "RestPose",
        ] where canPlay(fallback) {
            return fallback
        }
        return sheet.pack.animationNames.first ?? animationName
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

    private static func windowSize(frameSize: CGSize, bodyScale: SidekickBodyScale) -> CGSize {
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
