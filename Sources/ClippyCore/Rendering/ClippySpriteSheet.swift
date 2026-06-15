import AppKit
import SpriteKit

/// Loads a Clippy-compatible raster pack's sprite sheet, removes the magenta
/// chroma key, and slices per-animation frame textures for SpriteKit playback.
public final class ClippySpriteSheet {
    public let pack: RasterCharacterPack
    public let frameSize: CGSize

    private let keyedSheet: CGImage
    private let frameWidth: Int
    private let frameHeight: Int
    private var frameTextureCache: [String: SKTexture] = [:]

    public init(packRoot: URL) throws {
        let pack = try CharacterResourceLoader.loadRasterPack(from: packRoot)
        let mapURL = packRoot.appending(path: "map.png")
        guard
            let image = NSImage(contentsOf: mapURL),
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: mapURL.path])
        }
        self.pack = pack
        self.frameWidth = pack.frameSize.first ?? 124
        self.frameHeight = pack.frameSize.dropFirst().first ?? 93
        self.frameSize = CGSize(width: frameWidth, height: frameHeight)
        self.keyedSheet = try Self.removingChromaKey(from: source)
    }

    /// Returns the composited, chroma-keyed texture for a single frame,
    /// cached by the frame's layer coordinates.
    public func texture(for frame: RasterFrame) -> SKTexture? {
        guard let layers = frame.images, !layers.isEmpty else {
            return nil
        }
        let key = layers.flatMap { $0 }.map(String.init).joined(separator: ",")
        if let cached = frameTextureCache[key] {
            return cached
        }
        guard let image = composite(layers) else {
            return nil
        }
        let texture = SKTexture(cgImage: image)
        frameTextureCache[key] = texture
        return texture
    }

    public func frames(for animationName: String) -> (textures: [SKTexture], durations: [TimeInterval])? {
        guard let animation = pack.animations[animationName] else {
            return nil
        }
        var textures: [SKTexture] = []
        var durations: [TimeInterval] = []
        for frame in animation.frames {
            guard let layers = frame.images, !layers.isEmpty, let composited = composite(layers) else {
                continue
            }
            textures.append(SKTexture(cgImage: composited))
            durations.append(TimeInterval(frame.duration) / 1000)
        }
        guard !textures.isEmpty else {
            return nil
        }
        return (textures, durations)
    }

    private func composite(_ layers: [[Int]]) -> CGImage? {
        guard layers.count > 1 else {
            return cropFrame(at: layers[0])
        }
        guard let context = Self.makeContext(width: frameWidth, height: frameHeight) else {
            return nil
        }
        // Matches the MS Agent layer order used by Cosmo/Clippy: the first
        // image in the list is drawn last, on top.
        let bounds = CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
        for layer in layers.reversed() {
            guard let crop = cropFrame(at: layer) else {
                continue
            }
            context.draw(crop, in: bounds)
        }
        return context.makeImage()
    }

    private func cropFrame(at origin: [Int]) -> CGImage? {
        guard origin.count >= 2 else {
            return nil
        }
        let rect = CGRect(x: origin[0], y: origin[1], width: frameWidth, height: frameHeight)
        return keyedSheet.cropping(to: rect)
    }

    private static func removingChromaKey(from image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard let context = makeContext(width: width, height: height) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            let red = pixels[offset]
            let green = pixels[offset + 1]
            let blue = pixels[offset + 2]
            if red > 230, green < 60, blue > 230 {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
            }
        }
        guard let keyed = context.makeImage() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return keyed
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
