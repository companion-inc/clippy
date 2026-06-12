import CoreGraphics

public enum MorphTargetPreset: String, CaseIterable {
    case neutral
    case checkmark
    case question
    case magnifier
    case cursor
    case document
    case spinner

    public func path(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY

        switch self {
        case .neutral:
            path.addEllipse(in: CGRect(x: x + w * 0.18, y: y + h * 0.12, width: w * 0.64, height: h * 0.76))
        case .checkmark:
            path.move(to: CGPoint(x: x + w * 0.18, y: y + h * 0.48))
            path.addLine(to: CGPoint(x: x + w * 0.40, y: y + h * 0.25))
            path.addLine(to: CGPoint(x: x + w * 0.82, y: y + h * 0.72))
        case .question:
            path.move(to: CGPoint(x: x + w * 0.32, y: y + h * 0.66))
            path.addCurve(
                to: CGPoint(x: x + w * 0.58, y: y + h * 0.42),
                control1: CGPoint(x: x + w * 0.28, y: y + h * 0.88),
                control2: CGPoint(x: x + w * 0.82, y: y + h * 0.82)
            )
            path.addLine(to: CGPoint(x: x + w * 0.50, y: y + h * 0.28))
            path.move(to: CGPoint(x: x + w * 0.50, y: y + h * 0.14))
            path.addLine(to: CGPoint(x: x + w * 0.50, y: y + h * 0.14))
        case .magnifier:
            path.addEllipse(in: CGRect(x: x + w * 0.20, y: y + h * 0.34, width: w * 0.42, height: h * 0.42))
            path.move(to: CGPoint(x: x + w * 0.56, y: y + h * 0.34))
            path.addLine(to: CGPoint(x: x + w * 0.78, y: y + h * 0.16))
        case .cursor:
            path.move(to: CGPoint(x: x + w * 0.25, y: y + h * 0.82))
            path.addLine(to: CGPoint(x: x + w * 0.72, y: y + h * 0.48))
            path.addLine(to: CGPoint(x: x + w * 0.52, y: y + h * 0.40))
            path.addLine(to: CGPoint(x: x + w * 0.62, y: y + h * 0.16))
            path.addLine(to: CGPoint(x: x + w * 0.48, y: y + h * 0.12))
            path.addLine(to: CGPoint(x: x + w * 0.38, y: y + h * 0.36))
            path.closeSubpath()
        case .document:
            path.addRoundedRect(in: CGRect(x: x + w * 0.25, y: y + h * 0.14, width: w * 0.50, height: h * 0.72), cornerWidth: 8, cornerHeight: 8)
            path.move(to: CGPoint(x: x + w * 0.36, y: y + h * 0.62))
            path.addLine(to: CGPoint(x: x + w * 0.64, y: y + h * 0.62))
            path.move(to: CGPoint(x: x + w * 0.36, y: y + h * 0.48))
            path.addLine(to: CGPoint(x: x + w * 0.64, y: y + h * 0.48))
            path.move(to: CGPoint(x: x + w * 0.36, y: y + h * 0.34))
            path.addLine(to: CGPoint(x: x + w * 0.56, y: y + h * 0.34))
        case .spinner:
            path.addArc(center: CGPoint(x: x + w / 2, y: y + h / 2), radius: min(w, h) * 0.28, startAngle: 0.2, endAngle: 5.0, clockwise: false)
        }

        return path
    }
}
