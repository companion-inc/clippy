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
        sprite.anchorPoint = CGPoint(x: 0, y: 0)
        scene.addChild(sprite)
        view.allowsTransparency = true
        view.presentScene(scene)
    }

    public func show(texture: SKTexture) {
        texture.filteringMode = .nearest
        sprite.texture = texture
        sprite.size = texture.size()
    }

    public func play(textures: [SKTexture], frameDurations: [TimeInterval]) {
        guard !textures.isEmpty else {
            return
        }
        let actions = zip(textures, frameDurations).map { texture, duration in
            texture.filteringMode = .nearest
            return SKAction.setTexture(texture, resize: true).then(SKAction.wait(forDuration: duration))
        }
        sprite.run(SKAction.sequence(actions))
    }
}

private extension SKAction {
    func then(_ next: SKAction) -> SKAction {
        SKAction.sequence([self, next])
    }
}
