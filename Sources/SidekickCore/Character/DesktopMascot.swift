import AppKit
import SpriteKit

public enum MascotAnimationEndState: Equatable, Sendable {
    case waiting
    case exited
}

@MainActor
public protocol DesktopMascot: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var theme: MascotTheme { get }
    var windowController: MascotWindowController { get }
    var frame: CGRect { get }
    var idleAnimationNames: [String] { get }
    var gestureAnimationNames: [String] { get }
    var currentAnimationName: String? { get }
    var isMuted: Bool { get set }

    func show()
    @discardableResult
    func play(_ animationName: String, onEnd: ((String, MascotAnimationEndState) -> Void)?) -> Bool
    func exitCurrentAnimation()
    func move(to origin: CGPoint, animated: Bool)
    func park(in visibleFrame: CGRect, edge: MascotParkEdge)
    func point(at rect: CGRect)
    func snapshotPNGData() -> Data?
}

public enum MascotParkEdge: String, Equatable, Sendable {
    case lowerLeft
    case lowerRight
    case upperLeft
    case upperRight
}

public extension DesktopMascot {
    var frame: CGRect {
        windowController.frame
    }

    func show() {
        windowController.show()
    }

    func move(to origin: CGPoint, animated: Bool = true) {
        windowController.move(to: origin, animated: animated)
    }

    func park(in visibleFrame: CGRect, edge: MascotParkEdge) {
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

    func point(at rect: CGRect) {
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
}

@MainActor
public final class ClippyMascot: DesktopMascot {
    public let id = "clippy"
    public let displayName = "Clippy"
    public let theme = MascotTheme.clippy
    public let windowController: MascotWindowController
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
        self.windowController = MascotWindowController(rendererView: renderer.view, size: size) { point in
            CGRect(origin: .zero, size: size).contains(point)
        }
    }

    public var currentAnimationName: String? {
        animator.currentAnimationName
    }

    public var isMuted: Bool {
        get { soundBank?.isMuted ?? false }
        set { soundBank?.isMuted = newValue }
    }

    @discardableResult
    public func play(_ animationName: String, onEnd: ((String, MascotAnimationEndState) -> Void)? = nil) -> Bool {
        animator.play(animationName) { name, endState in
            let mapped: MascotAnimationEndState = endState == .waiting ? .waiting : .exited
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

@MainActor
public final class MorphMascot: DesktopMascot {
    public let id = "morph"
    public let displayName = "Morph Mascot"
    public let theme = MascotTheme.morph
    public let renderer = CoreAnimationMorphRenderer()
    public let windowController: MascotWindowController
    public let idleAnimationNames = ["Idle", "Blink", "Glance", "RaiseBrows", "Sway"]
    public let gestureAnimationNames = ["GetAttention", "Explain", "Alert", "Wave"]
    public private(set) var currentAnimationName: String?
    public var isMuted = false

    public init() {
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
        switch animationName {
        case "Greeting":
            renderer.appear()
        case "Blink":
            renderer.blink()
        case "Glance":
            renderer.glance()
        case "RaiseBrows":
            renderer.raiseBrows()
        case "Sway":
            renderer.sway()
        default:
            renderer.performNamedGesture()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.currentAnimationName = nil
            onEnd?(animationName, .exited)
        }
        return true
    }

    public func exitCurrentAnimation() {
        currentAnimationName = nil
    }

    public func snapshotPNGData() -> Data? {
        nil
    }
}
