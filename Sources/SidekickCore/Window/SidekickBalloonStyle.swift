import AppKit

/// Shared MS Agent-style balloon drawing. Sidekick's body is raster, but the
/// original Office Assistant balloon itself uses rounded corners and a smooth
/// single outline.
public enum SidekickBalloonStyle {
    public enum TailEdge: Equatable {
        case bottom
        case left
        case right
    }

    public static func font(_ size: CGFloat, bold: Bool = false, spec: SidekickBalloonSpec = .current) -> NSFont {
        let name = bold ? spec.boldFontName : spec.regularFontName
        if let font = NSFont(name: name, size: size) {
            return font
        }
        let fallback = NSFont(name: spec.regularFontName, size: size) ?? .systemFont(ofSize: size)
        return bold ? NSFontManager.shared.convert(fallback, toHaveTrait: .boldFontMask) : fallback
    }

    public static func makeShapeLayer(spec: SidekickBalloonSpec = .current) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = spec.fillColor.cgColor
        layer.strokeColor = spec.strokeColor.cgColor
        layer.lineWidth = spec.borderWidth
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.allowsEdgeAntialiasing = true
        layer.lineJoin = .round
        layer.lineCap = .round
        return layer
    }

    public static func path(
        size: CGSize,
        spec: SidekickBalloonSpec = .current,
        tailEdge: TailEdge = .bottom,
        tailTipPosition: CGFloat? = nil
    ) -> CGPath {
        switch tailEdge {
        case .bottom:
            bottomTailPath(size: size, spec: spec, tailTipX: tailTipPosition)
        case .left:
            sideTailPath(size: size, spec: spec, edge: .left, tailTipY: tailTipPosition)
        case .right:
            sideTailPath(size: size, spec: spec, edge: .right, tailTipY: tailTipPosition)
        }
    }

    private static func bottomTailPath(size: CGSize, spec: SidekickBalloonSpec, tailTipX: CGFloat?) -> CGPath {
        let inset: CGFloat = 0.5
        let left = inset, right = size.width - inset
        let bottom = spec.tailHeight, top = size.height - inset
        let radius = min(spec.cornerRadius, (right - left) / 2, (top - bottom) / 2)
        let minTailX = left + radius + 4
        let maxTailX = right - radius - 4
        let tipX = clamped(tailTipX ?? size.width * 0.5 + spec.tailTipOffset, min: minTailX, max: maxTailX)
        let tailLeftX = max(minTailX, tipX - spec.tailHalfWidth)
        let tailRightX = min(maxTailX, tipX + spec.tailHalfWidth)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + radius, y: bottom))
        path.addLine(to: CGPoint(x: tailLeftX, y: bottom))
        path.addLine(to: CGPoint(x: tipX, y: inset))
        path.addLine(to: CGPoint(x: tailRightX, y: bottom))
        path.addLine(to: CGPoint(x: right - radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom + radius), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: top - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: top), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: left + radius, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top - radius), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom + radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: bottom), control: CGPoint(x: left, y: bottom))
        path.closeSubpath()
        return path
    }

    private static func sideTailPath(
        size: CGSize,
        spec: SidekickBalloonSpec,
        edge: TailEdge,
        tailTipY: CGFloat?
    ) -> CGPath {
        let inset: CGFloat = 0.5
        let bodyLeft = edge == .left ? spec.tailHeight : inset
        let bodyRight = edge == .right ? size.width - spec.tailHeight : size.width - inset
        let bottom = inset
        let top = size.height - inset
        let radius = min(spec.cornerRadius, (bodyRight - bodyLeft) / 2, (top - bottom) / 2)
        let minTailY = bottom + radius + 4
        let maxTailY = top - radius - 4
        let tipY = clamped(tailTipY ?? size.height * 0.5, min: minTailY, max: maxTailY)
        let tailBottomY = max(minTailY, tipY - spec.tailHalfWidth)
        let tailTopY = min(maxTailY, tipY + spec.tailHalfWidth)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: bodyLeft + radius, y: bottom))
        path.addLine(to: CGPoint(x: bodyRight - radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: bodyRight, y: bottom + radius), control: CGPoint(x: bodyRight, y: bottom))

        if edge == .right {
            path.addLine(to: CGPoint(x: bodyRight, y: tailBottomY))
            path.addLine(to: CGPoint(x: size.width - inset, y: tipY))
            path.addLine(to: CGPoint(x: bodyRight, y: tailTopY))
        }

        path.addLine(to: CGPoint(x: bodyRight, y: top - radius))
        path.addQuadCurve(to: CGPoint(x: bodyRight - radius, y: top), control: CGPoint(x: bodyRight, y: top))
        path.addLine(to: CGPoint(x: bodyLeft + radius, y: top))
        path.addQuadCurve(to: CGPoint(x: bodyLeft, y: top - radius), control: CGPoint(x: bodyLeft, y: top))

        if edge == .left {
            path.addLine(to: CGPoint(x: bodyLeft, y: tailTopY))
            path.addLine(to: CGPoint(x: inset, y: tipY))
            path.addLine(to: CGPoint(x: bodyLeft, y: tailBottomY))
        }

        path.addLine(to: CGPoint(x: bodyLeft, y: bottom + radius))
        path.addQuadCurve(to: CGPoint(x: bodyLeft + radius, y: bottom), control: CGPoint(x: bodyLeft, y: bottom))
        path.closeSubpath()
        return path
    }

    private static func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard maxValue >= minValue else { return minValue }
        return min(max(value, minValue), maxValue)
    }
}
