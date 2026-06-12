import AppKit
import QuartzCore

public struct PixelSidekickStyle {
    public let bodyColor: NSColor
    public let secondaryColor: NSColor
    public let screenColor: NSColor
    public let accentColor: NSColor
    public let eyeColor: NSColor
    public let outlineColor: NSColor
    public let errorColor: NSColor
    public let shadowColor: NSColor

    public init(
        bodyColor: NSColor,
        secondaryColor: NSColor,
        screenColor: NSColor,
        accentColor: NSColor,
        eyeColor: NSColor,
        outlineColor: NSColor,
        errorColor: NSColor,
        shadowColor: NSColor
    ) {
        self.bodyColor = bodyColor
        self.secondaryColor = secondaryColor
        self.screenColor = screenColor
        self.accentColor = accentColor
        self.eyeColor = eyeColor
        self.outlineColor = outlineColor
        self.errorColor = errorColor
        self.shadowColor = shadowColor
    }

    public static let claudeCode = PixelSidekickStyle(
        bodyColor: NSColor(calibratedRed: 0.74, green: 0.33, blue: 0.20, alpha: 1),
        secondaryColor: NSColor(calibratedRed: 0.93, green: 0.74, blue: 0.54, alpha: 1),
        screenColor: NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.73, alpha: 1),
        accentColor: NSColor(calibratedRed: 0.20, green: 0.12, blue: 0.10, alpha: 1),
        eyeColor: NSColor(calibratedRed: 0.08, green: 0.06, blue: 0.05, alpha: 1),
        outlineColor: NSColor(calibratedRed: 0.13, green: 0.07, blue: 0.05, alpha: 1),
        errorColor: NSColor(calibratedRed: 0.82, green: 0.05, blue: 0.08, alpha: 1),
        shadowColor: NSColor.black.withAlphaComponent(0.22)
    )

    public static let codex = PixelSidekickStyle(
        bodyColor: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.12, alpha: 1),
        secondaryColor: NSColor(calibratedRed: 0.18, green: 0.23, blue: 0.28, alpha: 1),
        screenColor: NSColor(calibratedRed: 0.74, green: 1.00, blue: 0.78, alpha: 1),
        accentColor: NSColor(calibratedRed: 0.10, green: 0.70, blue: 0.46, alpha: 1),
        eyeColor: NSColor(calibratedRed: 0.04, green: 0.22, blue: 0.14, alpha: 1),
        outlineColor: NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 1),
        errorColor: NSColor(calibratedRed: 1.00, green: 0.17, blue: 0.18, alpha: 1),
        shadowColor: NSColor.black.withAlphaComponent(0.28)
    )
}

@MainActor
public final class PixelSidekickRenderer {
    public let rootLayer = CALayer()
    public let bounds = CGRect(x: 0, y: 0, width: 128, height: 128)

    private let style: PixelSidekickStyle
    private var blocks: [CALayer] = []
    private let unit: CGFloat = 8

    public init(style: PixelSidekickStyle) {
        self.style = style
        rootLayer.frame = bounds
        rootLayer.backgroundColor = NSColor.clear.cgColor
        rootLayer.magnificationFilter = .nearest
        rootLayer.minificationFilter = .nearest
        show("Idle")
    }

    public func show(_ animationName: String) {
        clear()
        drawPose(animationName)
    }

    public func containsVisiblePoint(_ point: CGPoint) -> Bool {
        CGRect(x: 24, y: 12, width: 80, height: 100).contains(point)
    }

    public func snapshotPNGData() -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width),
            pixelsHigh: Int(bounds.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        guard let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
            return nil
        }
        rootLayer.render(in: context)
        return rep.representation(using: .png, properties: [:])
    }

    private func clear() {
        blocks.forEach { $0.removeFromSuperlayer() }
        blocks.removeAll()
        rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    private func drawPose(_ animationName: String) {
        let pose = PixelPose(animationName)
        drawShadow(pose: pose)
        drawLegs(pose: pose)
        drawBody(pose: pose)
        drawHead(pose: pose)
        drawFace(pose: pose)
        drawArms(pose: pose)
        drawProp(pose: pose)
        animate(pose: pose)
    }

    private func drawShadow(pose: PixelPose) {
        let width: CGFloat = pose == .sleeping ? 10 : 8
        block(x: 4, y: 1, w: width, h: 1, color: style.shadowColor)
    }

    private func drawLegs(pose: PixelPose) {
        if pose == .sleeping {
            block(x: 4, y: 3, w: 8, h: 2, color: style.outlineColor)
            block(x: 5, y: 4, w: 6, h: 1, color: style.secondaryColor)
            return
        }
        block(x: 5, y: 2, w: 2, h: 2, color: style.outlineColor)
        block(x: 9, y: 2, w: 2, h: 2, color: style.outlineColor)
        block(x: 5, y: 3, w: 2, h: 1, color: style.secondaryColor)
        block(x: 9, y: 3, w: 2, h: 1, color: style.secondaryColor)
    }

    private func drawBody(pose: PixelPose) {
        let bodyY: CGFloat = pose == .sleeping ? 5 : 4
        block(x: 3, y: bodyY, w: 10, h: 7, color: style.outlineColor)
        block(x: 4, y: bodyY + 1, w: 8, h: 5, color: style.bodyColor)
        block(x: 5, y: bodyY + 2, w: 6, h: 3, color: style.screenColor)

        if pose == .working || pose == .thinking {
            block(x: 6, y: bodyY + 3, w: 1, h: 1, color: style.accentColor)
            block(x: 8, y: bodyY + 3, w: 2, h: 1, color: style.accentColor)
        } else if pose == .attention {
            block(x: 6, y: bodyY + 3, w: 4, h: 1, color: style.accentColor)
        } else {
            block(x: 6, y: bodyY + 3, w: 3, h: 1, color: style.accentColor)
        }
    }

    private func drawHead(pose: PixelPose) {
        let headY: CGFloat = pose == .sleeping ? 9 : 10
        block(x: 4, y: headY, w: 8, h: 5, color: style.outlineColor)
        block(x: 5, y: headY + 1, w: 6, h: 3, color: style.secondaryColor)
        if pose != .sleeping {
            block(x: 7, y: headY + 5, w: 2, h: 1, color: style.outlineColor)
            block(x: 8, y: headY + 6, w: 1, h: 1, color: style.accentColor)
        }
    }

    private func drawFace(pose: PixelPose) {
        let eyeY: CGFloat = pose == .sleeping ? 11 : 13
        switch pose {
        case .error:
            drawX(x: 6, y: eyeY, color: style.errorColor)
            drawX(x: 9, y: eyeY, color: style.errorColor)
        case .sleeping:
            block(x: 6, y: eyeY, w: 2, h: 1, color: style.eyeColor)
            block(x: 9, y: eyeY, w: 2, h: 1, color: style.eyeColor)
        default:
            block(x: 6, y: eyeY, w: 1, h: 1, color: style.eyeColor)
            block(x: 9, y: eyeY, w: 1, h: 1, color: style.eyeColor)
        }

        if pose == .attention {
            block(x: 7, y: 11, w: 3, h: 1, color: style.eyeColor)
        } else if pose == .error {
            block(x: 7, y: 11, w: 3, h: 1, color: style.errorColor)
        } else {
            block(x: 7, y: pose == .sleeping ? 10 : 11, w: 2, h: 1, color: style.eyeColor)
        }
    }

    private func drawArms(pose: PixelPose) {
        switch pose {
        case .attention:
            block(x: 1, y: 10, w: 3, h: 1, color: style.outlineColor)
            block(x: 12, y: 10, w: 3, h: 1, color: style.outlineColor)
            block(x: 2, y: 11, w: 1, h: 2, color: style.outlineColor)
            block(x: 14, y: 11, w: 1, h: 2, color: style.outlineColor)
        case .working:
            block(x: 1, y: 6, w: 3, h: 1, color: style.outlineColor)
            block(x: 12, y: 6, w: 3, h: 1, color: style.outlineColor)
        case .sleeping:
            block(x: 2, y: 6, w: 2, h: 1, color: style.outlineColor)
            block(x: 12, y: 6, w: 2, h: 1, color: style.outlineColor)
        default:
            block(x: 2, y: 7, w: 2, h: 1, color: style.outlineColor)
            block(x: 12, y: 7, w: 2, h: 1, color: style.outlineColor)
        }
    }

    private func drawProp(pose: PixelPose) {
        switch pose {
        case .thinking:
            block(x: 11, y: 14, w: 1, h: 1, color: style.screenColor)
            block(x: 12, y: 15, w: 1, h: 1, color: style.screenColor)
            block(x: 13, y: 14, w: 1, h: 1, color: style.screenColor)
        case .working:
            block(x: 1, y: 4, w: 14, h: 1, color: style.outlineColor)
            block(x: 3, y: 5, w: 10, h: 1, color: style.accentColor)
        case .juggling:
            block(x: 4, y: 15, w: 1, h: 1, color: style.accentColor)
            block(x: 8, y: 16, w: 1, h: 1, color: style.screenColor)
            block(x: 12, y: 15, w: 1, h: 1, color: style.secondaryColor)
        case .notification:
            block(x: 13, y: 11, w: 2, h: 4, color: style.outlineColor)
            block(x: 14, y: 12, w: 1, h: 2, color: style.screenColor)
            block(x: 14, y: 11, w: 1, h: 1, color: style.errorColor)
        case .sweeping:
            block(x: 12, y: 3, w: 1, h: 6, color: style.outlineColor)
            block(x: 11, y: 2, w: 4, h: 1, color: style.accentColor)
        case .carrying:
            block(x: 12, y: 5, w: 3, h: 3, color: style.outlineColor)
            block(x: 13, y: 6, w: 1, h: 1, color: style.screenColor)
        default:
            break
        }
    }

    private func drawX(x: CGFloat, y: CGFloat, color: NSColor) {
        block(x: x, y: y, w: 1, h: 1, color: color)
        block(x: x + 1, y: y + 1, w: 1, h: 1, color: color)
        block(x: x + 1, y: y, w: 1, h: 1, color: color)
        block(x: x, y: y + 1, w: 1, h: 1, color: color)
    }

    @discardableResult
    private func block(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: NSColor) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit)
        layer.backgroundColor = color.cgColor
        layer.allowsEdgeAntialiasing = false
        layer.contentsScale = 1
        rootLayer.addSublayer(layer)
        blocks.append(layer)
        return layer
    }

    private func animate(pose: PixelPose) {
        guard pose == .working || pose == .thinking || pose == .juggling else {
            return
        }
        let bounce = CABasicAnimation(keyPath: "transform.translation.y")
        bounce.fromValue = 0
        bounce.toValue = pose == .thinking ? 3 : 5
        bounce.duration = pose == .thinking ? 0.55 : 0.32
        bounce.autoreverses = true
        bounce.repeatCount = 2
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rootLayer.add(bounce, forKey: "pixel-bounce")
    }
}

private enum PixelPose: Equatable {
    case idle
    case thinking
    case working
    case juggling
    case notification
    case attention
    case error
    case sweeping
    case carrying
    case sleeping

    init(_ animationName: String) {
        let normalized = animationName.lowercased()
        if normalized.contains("think") || normalized.contains("glance") {
            self = .thinking
        } else if normalized.contains("work") || normalized.contains("typ") || normalized.contains("sway") {
            self = .working
        } else if normalized.contains("juggl") || normalized.contains("brow") {
            self = .juggling
        } else if normalized.contains("notif") || normalized.contains("alert") {
            self = .notification
        } else if normalized.contains("attention") || normalized.contains("celebrate") || normalized.contains("happy") || normalized.contains("wave") {
            self = .attention
        } else if normalized.contains("error") {
            self = .error
        } else if normalized.contains("sweep") {
            self = .sweeping
        } else if normalized.contains("carry") {
            self = .carrying
        } else if normalized.contains("sleep") {
            self = .sleeping
        } else {
            self = .idle
        }
    }
}
