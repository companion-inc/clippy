import AppKit
import QuartzCore

/// Clippy's original vector body: a paperclip character drawn entirely with
/// Core Animation layers — no sprite assets. The wire is one stroked bezier
/// path (so it can morph), the face is separate layers so eyes, pupils, and
/// brows animate independently. Idle behaviors run as lightweight random
/// gestures: blinks, pupil glances, brow raises, and a gentle sway.
@MainActor
public final class CoreAnimationMorphRenderer {
    public let rootLayer = CALayer()
    public let bounds = CGRect(x: 0, y: 0, width: 140, height: 180)

    private let characterLayer = CALayer()
    private let bodyLayer = CAShapeLayer()
    private let leftEye = CAShapeLayer()
    private let rightEye = CAShapeLayer()
    private let leftPupil = CAShapeLayer()
    private let rightPupil = CAShapeLayer()
    private let leftBrow = CAShapeLayer()
    private let rightBrow = CAShapeLayer()
    private var idleTask: Task<Void, Never>?

    private static let headCenter = CGPoint(x: 70, y: 112)
    private static let headRadius: CGFloat = 34

    public init() {
        rootLayer.frame = bounds
        rootLayer.backgroundColor = NSColor.clear.cgColor

        characterLayer.frame = bounds
        // Sway pivots around the lower body, like the sprite Clippit.
        characterLayer.anchorPoint = CGPoint(x: 0.5, y: 0.25)
        characterLayer.position = CGPoint(x: bounds.midX, y: bounds.height * 0.25)
        rootLayer.addSublayer(characterLayer)

        bodyLayer.frame = bounds
        bodyLayer.fillColor = NSColor.clear.cgColor
        bodyLayer.strokeColor = NSColor(calibratedWhite: 0.58, alpha: 1).cgColor
        bodyLayer.lineWidth = 9
        bodyLayer.lineCap = .round
        bodyLayer.lineJoin = .round
        bodyLayer.path = Self.paperclipPath()
        bodyLayer.shadowColor = NSColor.black.cgColor
        bodyLayer.shadowOpacity = 0.25
        bodyLayer.shadowRadius = 2
        bodyLayer.shadowOffset = CGSize(width: 0, height: -1.5)
        characterLayer.addSublayer(bodyLayer)

        setupEye(leftEye, pupil: leftPupil, center: CGPoint(x: 57, y: 124))
        setupEye(rightEye, pupil: rightPupil, center: CGPoint(x: 83, y: 124))
        setupBrow(leftBrow, center: CGPoint(x: 57, y: 140))
        setupBrow(rightBrow, center: CGPoint(x: 83, y: 140))
    }

    // MARK: - Entrances and gestures

    /// Springs the character in from small — the "appear" beat.
    public func appear() {
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.25
        spring.toValue = 1.0
        spring.damping = 11
        spring.initialVelocity = 4
        spring.duration = spring.settlingDuration
        characterLayer.add(spring, forKey: "appear")
    }

    /// Starts the random idle gesture loop. Cancel by calling again or deinit.
    public func startIdleBehaviors() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 1.6...4.2)))
                guard !Task.isCancelled, let self else {
                    return
                }
                self.performRandomGesture()
            }
        }
    }

    public func blink() {
        for eye in [leftEye, rightEye] {
            let squeeze = CABasicAnimation(keyPath: "transform.scale.y")
            squeeze.fromValue = 1.0
            squeeze.toValue = 0.08
            squeeze.duration = 0.07
            squeeze.autoreverses = true
            squeeze.timingFunction = CAMediaTimingFunction(name: .easeIn)
            eye.add(squeeze, forKey: "blink")
        }
    }

    public func glance() {
        let offset = CGPoint(
            x: CGFloat.random(in: -3.2...3.2),
            y: CGFloat.random(in: -2.5...1.5)
        )
        for pupil in [leftPupil, rightPupil] {
            let look = CAKeyframeAnimation(keyPath: "position")
            let home = pupil.position
            let away = CGPoint(x: home.x + offset.x, y: home.y + offset.y)
            look.values = [home, away, away, home].map { NSValue(point: $0) }
            look.keyTimes = [0, 0.15, 0.8, 1]
            look.duration = 1.4
            look.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pupil.add(look, forKey: "glance")
        }
    }

    public func raiseBrows() {
        for brow in [leftBrow, rightBrow] {
            let raise = CAKeyframeAnimation(keyPath: "position.y")
            let home = brow.position.y
            raise.values = [home, home + 5, home + 5, home]
            raise.keyTimes = [0, 0.2, 0.75, 1]
            raise.duration = 0.9
            raise.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            brow.add(raise, forKey: "raise")
        }
    }

    public func sway() {
        let lean = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        lean.values = [0, 0.055, -0.04, 0]
        lean.keyTimes = [0, 0.3, 0.7, 1]
        lean.duration = 1.3
        lean.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        characterLayer.add(lean, forKey: "sway")
    }

    /// Morphs the wire body into another shape (checkmark, magnifier, …) and
    /// back later — the modern equivalent of Clippit's shape-shifting frames.
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
        // The head disc makes the face easy to grab.
        let dx = point.x - Self.headCenter.x
        let dy = point.y - Self.headCenter.y
        if dx * dx + dy * dy <= Self.headRadius * Self.headRadius {
            return true
        }
        if let path = bodyLayer.presentation()?.path ?? bodyLayer.path {
            let stroked = path.copy(
                strokingWithWidth: max(18, bodyLayer.lineWidth),
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 0
            )
            return stroked.contains(point)
        }
        return false
    }

    // MARK: - Geometry

    /// The wire: one continuous stroke spiraling inward, end rounded by caps.
    private static func paperclipPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 36, y: 40))
        path.addLine(to: CGPoint(x: 36, y: 112))
        path.addArc(
            center: headCenter, radius: headRadius,
            startAngle: .pi, endAngle: 0, clockwise: true
        )
        path.addLine(to: CGPoint(x: 104, y: 44))
        path.addArc(
            center: CGPoint(x: 78, y: 44), radius: 26,
            startAngle: 0, endAngle: .pi, clockwise: false
        )
        path.addLine(to: CGPoint(x: 52, y: 104))
        path.addArc(
            center: CGPoint(x: 70.5, y: 104), radius: 18.5,
            startAngle: .pi, endAngle: 0, clockwise: true
        )
        path.addLine(to: CGPoint(x: 89, y: 60))
        return path
    }

    private func setupEye(_ eye: CAShapeLayer, pupil: CAShapeLayer, center: CGPoint) {
        let eyeSize = CGSize(width: 17, height: 21)
        eye.bounds = CGRect(origin: .zero, size: eyeSize)
        eye.position = center
        eye.path = CGPath(ellipseIn: eye.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        eye.fillColor = NSColor.white.cgColor
        eye.strokeColor = NSColor.black.cgColor
        eye.lineWidth = 1.8
        characterLayer.addSublayer(eye)

        pupil.bounds = CGRect(x: 0, y: 0, width: 6.5, height: 6.5)
        pupil.position = CGPoint(x: center.x, y: center.y - 2)
        pupil.path = CGPath(ellipseIn: pupil.bounds, transform: nil)
        pupil.fillColor = NSColor.black.cgColor
        characterLayer.addSublayer(pupil)
    }

    private func setupBrow(_ brow: CAShapeLayer, center: CGPoint) {
        brow.bounds = CGRect(x: 0, y: 0, width: 18, height: 8)
        brow.position = center
        let arc = CGMutablePath()
        arc.move(to: CGPoint(x: 1, y: 2))
        arc.addQuadCurve(to: CGPoint(x: 17, y: 2), control: CGPoint(x: 9, y: 9))
        brow.path = arc
        brow.fillColor = NSColor.clear.cgColor
        brow.strokeColor = NSColor.black.cgColor
        brow.lineWidth = 2.4
        brow.lineCap = .round
        characterLayer.addSublayer(brow)
    }

    private func performRandomGesture() {
        switch Int.random(in: 0..<100) {
        case 0..<55:
            blink()
        case 55..<80:
            glance()
        case 80..<92:
            raiseBrows()
        default:
            sway()
        }
    }
}
