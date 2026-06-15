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

    public let idleAnimationNames = [
        "Idle1_1", "IdleAtom", "IdleEyeBrowRaise", "IdleFingerTap",
        "IdleHeadScratch", "IdleRopePile", "IdleSideToSide", "IdleSnooze",
        "LookLeft", "LookRight",
    ]
    public let gestureAnimationNames = [
        "Congratulate", "GetAttention", "Wave", "Print", "Save", "GetArtsy",
        "GetTechy", "GetWizardy", "Explain", "Alert", "CheckingSomething",
        "EmptyTrash", "SendMail", "Writing", "Processing",
    ]

    public init(packRoot: URL, scale: CGFloat = 2) throws {
        let sheet = try ClippySpriteSheet(packRoot: packRoot)
        let size = CGSize(width: sheet.frameSize.width * scale, height: sheet.frameSize.height * scale)
        let renderer = SpriteKitRasterCharacterRenderer(size: size)
        let animator = ClippyAnimator(sheet: sheet, renderer: renderer)
        let soundBank = try? ClippySoundBank(packRoot: packRoot)
        animator.soundBank = soundBank

        self.renderer = renderer
        self.animator = animator
        self.soundBank = soundBank
        self.windowController = ClippyWindowController(rendererView: renderer.view, size: size) { point in
            CGRect(origin: .zero, size: size).contains(point)
        }
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
}
