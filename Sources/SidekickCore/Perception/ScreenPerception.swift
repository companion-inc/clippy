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
        guard let target = mainScreenForCapture(),
              let image = CGDisplayCreateImage(target.displayID) else {
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
        public let screenFrame: CGRect
        public let screenIndex: Int

        public init(path: String, pixelSize: CGSize, screenFrame: CGRect, screenIndex: Int) {
            self.path = path
            self.pixelSize = pixelSize
            self.screenFrame = screenFrame
            self.screenIndex = screenIndex
        }
    }

    /// Capture one display to a JPEG on disk (overwriting the previous one) and
    /// return its path + pixel size. This is how Sidekick gets *eyes*: the model
    /// `Read`s this file to see the same screen Sidekick is on, then points in its
    /// pixel space.
    public static func captureToFile(
        screen requestedScreen: NSScreen? = nil,
        maxDimension: Int = 1600,
        compression: CGFloat = 0.7,
        belowWindowNumber: Int? = nil,
        directory: URL? = nil,
        fileName: String = "screen.jpg"
    ) -> Screenshot? {
        guard let target = captureTarget(for: requestedScreen) ?? mainScreenForCapture() else { return nil }
        guard let image = captureImage(displayID: target.displayID, belowWindowNumber: belowWindowNumber),
              let scaled = try? scale(image: image, maxDimension: maxDimension) else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaled)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: compression]) else { return nil }
        let url: URL
        if let directory {
            url = directory.appendingPathComponent(fileName)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            url = base.appendingPathComponent("Sidekick/\(fileName)")
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url)) != nil else { return nil }
        return Screenshot(
            path: url.path,
            pixelSize: CGSize(width: scaled.width, height: scaled.height),
            screenFrame: target.screen.frame,
            screenIndex: target.index
        )
    }

    /// Capture every connected display to stable per-screen JPEG files.
    public static func captureAllToFiles(
        directory: URL? = nil,
        fileNamePrefix: String = "screen",
        maxDimension: Int = 1600,
        compression: CGFloat = 0.7,
        belowWindowNumber: Int? = nil
    ) -> [Screenshot] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            let fileName = directory == nil && fileNamePrefix == "screen"
                ? "screen-\(index + 1).jpg"
                : "\(fileNamePrefix)-screen-\(index + 1).jpg"
            return captureToFile(
                screen: screen,
                maxDimension: maxDimension,
                compression: compression,
                belowWindowNumber: belowWindowNumber,
                directory: directory,
                fileName: fileName
            )
        }
    }

    private static func captureImage(displayID: CGDirectDisplayID, belowWindowNumber: Int?) -> CGImage? {
        if let belowWindowNumber,
           let image = CGWindowListCreateImage(
            CGDisplayBounds(displayID),
            .optionOnScreenBelowWindow,
            CGWindowID(belowWindowNumber),
            [.boundsIgnoreFraming, .bestResolution]
           ) {
            return image
        }
        return CGDisplayCreateImage(displayID)
    }

    /// Pick the screen Sidekick should consider itself on. Use intersection area
    /// first so a partially-dragged window belongs to the display it mostly occupies.
    public static func screen(containing frame: CGRect, screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        let frames = screens.map(\.frame)
        guard let index = bestScreenIndex(for: frame, screenFrames: frames),
              screens.indices.contains(index) else { return nil }
        return screens[index]
    }

    public static func bestScreenIndex(for frame: CGRect, screenFrames: [CGRect]) -> Int? {
        guard !screenFrames.isEmpty else { return nil }

        let areas = screenFrames.enumerated().map { index, screenFrame -> (index: Int, area: CGFloat) in
            let intersection = frame.intersection(screenFrame)
            guard !intersection.isNull else { return (index, 0) }
            return (index, max(0, intersection.width) * max(0, intersection.height))
        }
        if let best = areas.max(by: { $0.area < $1.area }), best.area > 0 {
            return best.index
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let containing = screenFrames.firstIndex(where: { $0.contains(center) }) {
            return containing
        }

        return screenFrames.enumerated().min { lhs, rhs in
            distanceSquared(from: center, to: lhs.element) < distanceSquared(from: center, to: rhs.element)
        }?.offset
    }

    private static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        return dx * dx + dy * dy
    }

    private static func captureTarget(for requestedScreen: NSScreen?) -> (screen: NSScreen, index: Int, displayID: CGDirectDisplayID)? {
        guard let requestedScreen else { return nil }
        guard let requestedDisplayID = displayID(for: requestedScreen) else { return nil }
        let index = NSScreen.screens.firstIndex { screen in
            displayID(for: screen) == requestedDisplayID
        } ?? NSScreen.screens.firstIndex { $0 === requestedScreen } ?? 0
        return (requestedScreen, index, requestedDisplayID)
    }

    private static func mainScreenForCapture() -> (screen: NSScreen, index: Int, displayID: CGDirectDisplayID)? {
        let mainDisplayID = CGMainDisplayID()
        for (index, screen) in NSScreen.screens.enumerated() {
            if Self.displayID(for: screen) == mainDisplayID {
                return (screen, index, mainDisplayID)
            }
        }
        if let main = NSScreen.main {
            let index = NSScreen.screens.firstIndex { $0 === main } ?? 0
            return captureTarget(for: main) ?? Self.displayID(for: main).map { (main, index, $0) }
        }
        guard let first = NSScreen.screens.first,
              let firstDisplayID = displayID(for: first) else { return nil }
        return (first, 0, firstDisplayID)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
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
