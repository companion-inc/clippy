import AppKit

/// Shared MS Agent-style balloon drawing. Sidekick's body is raster, but the
/// original Office Assistant balloon itself uses rounded corners and a smooth
/// single outline.
public enum SidekickBalloonStyle {
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

    public static func path(size: CGSize, spec: SidekickBalloonSpec = .current) -> CGPath {
        let inset: CGFloat = 0.5
        let left = inset, right = size.width - inset
        let bottom = spec.tailHeight, top = size.height - inset
        let radius = min(spec.cornerRadius, (right - left) / 2, (top - bottom) / 2)
        let tailLeftX = max(left + radius + 4, size.width * 0.5 - spec.tailHalfWidth)
        let tailRightX = min(right - radius - 4, size.width * 0.5 + spec.tailHalfWidth)
        let tipX = size.width * 0.5 + spec.tailTipOffset

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
}
