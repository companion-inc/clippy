import Foundation
import SpriteKit

/// Frame stepper for Clippy-compatible animations. It preserves MS Agent-style
/// weighted random frame branching, exit branches, and exit-branching animations
/// that wait at their last frame until told to exit.
@MainActor
public final class SidekickAnimator {
    public enum AnimationEndState: Equatable {
        /// The animation uses exit branching and is holding at its last frame.
        case waiting
        /// The animation reached its end.
        case exited
    }

    public private(set) var currentAnimationName: String?
    public var isAnimationRunning: Bool { currentAnimation != nil }

    /// When set, frame sound ids play through this bank, matching the
    /// original's per-frame sound triggers.
    public var soundBank: SidekickSoundBank?

    private let sheet: SidekickSpriteSheet
    private let renderer: SpriteKitRasterCharacterRenderer

    private var currentAnimation: RasterAnimation?
    private var currentFrame: RasterFrame?
    private var currentFrameIndex = 0
    private var isExiting = false
    private var endHandler: ((String, AnimationEndState) -> Void)?
    private var pendingStep: DispatchWorkItem?

    public init(sheet: SidekickSpriteSheet, renderer: SpriteKitRasterCharacterRenderer) {
        self.sheet = sheet
        self.renderer = renderer
    }

    public var animationNames: [String] {
        sheet.pack.animationNames
    }

    @discardableResult
    public func play(
        _ animationName: String,
        onEnd: ((String, AnimationEndState) -> Void)? = nil
    ) -> Bool {
        guard let animation = sheet.pack.animations[animationName] else {
            return false
        }
        sheet.preloadTextures(for: [animationName])
        isExiting = false
        currentAnimation = animation
        currentAnimationName = animationName
        currentFrame = nil
        currentFrameIndex = 0
        endHandler = onEnd
        step()
        return true
    }

    /// Asks an exit-branching animation to leave via its exit frames.
    public func exitCurrentAnimation() {
        isExiting = true
    }

    public func stop() {
        pendingStep?.cancel()
        pendingStep = nil
        currentAnimation = nil
        endHandler = nil
    }

    func advanceFrameSynchronouslyForTesting() {
        pendingStep?.cancel()
        pendingStep = nil
        step()
    }

    private func step() {
        guard let animation = currentAnimation else {
            return
        }
        let lastIndex = animation.frames.count - 1
        let nextIndex = min(nextFrameIndex(), lastIndex)
        let frameChanged = currentFrame == nil || currentFrameIndex != nextIndex
        currentFrameIndex = nextIndex

        let atLastFrame = currentFrameIndex >= lastIndex
        let usesExitBranching = animation.useExitBranching ?? false
        let nextFrame = animation.frames[currentFrameIndex]
        let isBlankTerminator = atLastFrame && nextFrame.hasRenderableImages == false
        if !(atLastFrame && usesExitBranching) && isBlankTerminator == false {
            currentFrame = nextFrame
        }

        draw()
        if let sound = currentFrame?.sound {
            soundBank?.play(sound)
        }

        if frameChanged, atLastFrame, !(usesExitBranching && !isExiting) {
            currentAnimation = nil
            pendingStep = nil
            notifyEnd(.exited, oneShot: true)
            return
        }

        scheduleStep(afterMilliseconds: currentFrame?.duration ?? 100)

        if frameChanged, atLastFrame, usesExitBranching, !isExiting {
            notifyEnd(.waiting, oneShot: false)
        }
    }

    private func nextFrameIndex() -> Int {
        guard let frame = currentFrame else {
            return 0
        }
        if isExiting, let exitBranch = frame.exitBranch {
            return exitBranch
        }
        if let branching = frame.branching {
            var roll = Double.random(in: 0..<100)
            for branch in branching.branches {
                if roll <= Double(branch.weight) {
                    return branch.frameIndex
                }
                roll -= Double(branch.weight)
            }
        }
        return currentFrameIndex + 1
    }

    private func draw() {
        guard let frame = currentFrame, let texture = sheet.texture(for: frame) else {
            renderer.sprite.isHidden = true
            return
        }
        renderer.sprite.isHidden = false
        renderer.show(texture: texture)
    }

    private func scheduleStep(afterMilliseconds milliseconds: Int) {
        pendingStep?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.step()
        }
        pendingStep = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: work)
    }

    private func notifyEnd(_ state: AnimationEndState, oneShot: Bool) {
        guard let handler = endHandler, let name = currentAnimationName else {
            return
        }
        if oneShot {
            endHandler = nil
        }
        handler(name, state)
    }
}

private extension RasterFrame {
    var hasRenderableImages: Bool {
        guard let images, images.isEmpty == false else {
            return false
        }
        return images.contains { $0.count >= 2 }
    }
}
