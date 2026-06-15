import AppKit
import CoreGraphics

public enum ScreenPerception {
    public static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func captureMainDisplayJPEG(maxDimension: Int = 1600, compression: CGFloat = 0.82) throws -> Data {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw ScreenPerceptionError.captureFailed
        }
        let scaled = try scale(image: image, maxDimension: maxDimension)
        let rep = NSBitmapImageRep(cgImage: scaled)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: compression]) else {
            throw ScreenPerceptionError.encodingFailed
        }
        return data
    }

    /// A screenshot saved to disk, with the pixel size of the saved image so the
    /// model's coordinates can be mapped back to the screen.
    public struct Screenshot: Sendable {
        public let path: String
        public let pixelSize: CGSize
    }

    /// Capture the main display to a JPEG on disk (overwriting the previous one) and
    /// return its path + pixel size. This is how Clippy gets *eyes*: the model `Read`s
    /// this file to see the screen, then points in its pixel space.
    public static func captureToFile(maxDimension: Int = 1600, compression: CGFloat = 0.7) -> Screenshot? {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()),
              let scaled = try? scale(image: image, maxDimension: maxDimension) else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaled)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: compression]) else { return nil }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent("Clippy/screen.jpg")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url)) != nil else { return nil }
        return Screenshot(path: url.path, pixelSize: CGSize(width: scaled.width, height: scaled.height))
    }

    private static func scale(image: CGImage, maxDimension: Int) throws -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxDimension else {
            return image
        }
        let scale = CGFloat(maxDimension) / CGFloat(longest)
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ScreenPerceptionError.encodingFailed
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: .zero, size: size))
        guard let scaled = context.makeImage() else {
            throw ScreenPerceptionError.encodingFailed
        }
        return scaled
    }
}

public enum ScreenPerceptionError: Error {
    case captureFailed
    case encodingFailed
}
