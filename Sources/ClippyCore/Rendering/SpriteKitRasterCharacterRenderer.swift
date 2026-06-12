import AppKit
import SpriteKit

public final class SpriteKitRasterCharacterRenderer {
    public let view: SKView
    public let scene: SKScene
    public let sprite: SKSpriteNode

    public init(size: CGSize) {
        self.view = SKView(frame: CGRect(origin: .zero, size: size))
        self.scene = SKScene(size: size)
        self.sprite = SKSpriteNode()
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.position = CGPoint(x: size.width / 2, y: 0)
        scene.addChild(sprite)
        view.allowsTransparency = true
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.presentScene(scene)
    }

    public func show(texture: SKTexture) {
        texture.filteringMode = .nearest
        sprite.texture = texture
        sprite.size = fittedSize(for: texture)
    }

    public func show(animationName: String, spriteSheet: ClippitSpriteSheet) throws {
        guard let frames = spriteSheet.frames(for: animationName), let texture = frames.textures.first else {
            throw SpriteKitRasterCharacterRendererError.missingAnimationFrames(animationName)
        }
        show(texture: texture)
    }

    public func play(animationName: String, spriteSheet: ClippitSpriteSheet) throws {
        guard let frames = spriteSheet.frames(for: animationName) else {
            throw SpriteKitRasterCharacterRendererError.missingAnimationFrames(animationName)
        }
        play(textures: frames.textures, frameDurations: frames.durations)
    }

    public func play(textures: [SKTexture], frameDurations: [TimeInterval]) {
        guard !textures.isEmpty else {
            return
        }
        sprite.size = fittedSize(for: textures[0])
        let actions = zip(textures, frameDurations).map { texture, duration in
            texture.filteringMode = .nearest
            return SKAction.setTexture(texture, resize: false).then(SKAction.wait(forDuration: duration))
        }
        sprite.run(SKAction.sequence(actions))
    }

    private func fittedSize(for texture: SKTexture) -> CGSize {
        let original = texture.size()
        guard original.width > 0, original.height > 0 else {
            return .zero
        }
        let scale = min(scene.size.width / original.width, scene.size.height / original.height)
        return CGSize(width: original.width * scale, height: original.height * scale)
    }
}

public enum SpriteKitRasterCharacterRendererError: Error, Equatable {
    case missingAnimationFrames(String)
}

private extension SKAction {
    func then(_ next: SKAction) -> SKAction {
        SKAction.sequence([self, next])
    }
}
