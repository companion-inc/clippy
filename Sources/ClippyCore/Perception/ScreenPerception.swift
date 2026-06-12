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
