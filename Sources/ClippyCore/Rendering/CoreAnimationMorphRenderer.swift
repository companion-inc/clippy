import AppKit
import QuartzCore

public final class CoreAnimationMorphRenderer {
    public let rootLayer = CALayer()
    public let bounds = CGRect(x: 0, y: 0, width: 160, height: 160)

    private let bodyLayer = CAShapeLayer()
    private let leftEye = CAShapeLayer()
    private let rightEye = CAShapeLayer()

    public init() {
        rootLayer.frame = bounds
        rootLayer.backgroundColor = NSColor.clear.cgColor

        bodyLayer.frame = bounds
        bodyLayer.fillColor = NSColor.clear.cgColor
        bodyLayer.strokeColor = NSColor.systemYellow.cgColor
        bodyLayer.lineWidth = 10
        bodyLayer.lineCap = .round
        bodyLayer.lineJoin = .round
        bodyLayer.path = MorphTargetPreset.neutral.path(in: bounds)

        [leftEye, rightEye].forEach {
            $0.fillColor = NSColor.black.cgColor
            rootLayer.addSublayer($0)
        }

        rootLayer.addSublayer(bodyLayer)
        layoutEyes()
    }

    public func transition(to path: CGPath, duration: CFTimeInterval = 0.22) {
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = bodyLayer.presentation()?.path ?? bodyLayer.path
        animation.toValue = path
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bodyLayer.path = path
        bodyLayer.add(animation, forKey: "path")
    }

    public func containsVisiblePoint(_ point: CGPoint) -> Bool {
        guard bounds.contains(point) else {
            return false
        }
        if let path = bodyLayer.presentation()?.path ?? bodyLayer.path {
            let stroked = path.copy(strokingWithWidth: max(18, bodyLayer.lineWidth), lineCap: .round, lineJoin: .round, miterLimit: 0)
            return stroked.contains(point)
        }
        return false
    }

    private func layoutEyes() {
        leftEye.path = CGPath(ellipseIn: CGRect(x: 60, y: 92, width: 9, height: 9), transform: nil)
        rightEye.path = CGPath(ellipseIn: CGRect(x: 92, y: 92, width: 9, height: 9), transform: nil)
    }
}
