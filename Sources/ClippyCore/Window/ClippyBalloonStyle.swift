import AppKit

/// Shared MS Agent-style balloon drawing. The default Clippy body is raster and
/// nearest-neighbor; the balloon should read like the same low-resolution UI,
/// not like a modern AppKit panel.
public enum ClippyBalloonStyle {
    public static func font(_ size: CGFloat, bold: Bool = false, theme: MascotBalloonTheme = .clippy) -> NSFont {
        let name = bold ? theme.boldFontName : theme.regularFontName
        if let font = NSFont(name: name, size: size) {
            return font
        }
        let fallback = NSFont(name: theme.regularFontName, size: size) ?? .systemFont(ofSize: size)
        return bold ? NSFontManager.shared.convert(fallback, toHaveTrait: .boldFontMask) : fallback
    }

    /// A Clippy-style bubble layer: a tail-less rounded rectangle with continuous
    /// (squircle) corners, a hairline border, and a soft drop shadow — copied from
    /// Clippy's CompanionResponseOverlay (radius 10, 0.8pt border, shadow r16 y8).
    public static func makeLayer(theme: MascotBalloonTheme = .clippy) -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = theme.fillColor.cgColor
        layer.borderColor = theme.strokeColor.cgColor
        layer.borderWidth = theme.borderWidth
        layer.cornerRadius = theme.cornerRadius
        layer.cornerCurve = .continuous
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: -8) // below the bubble (y-up layer)
        layer.masksToBounds = false
        return layer
    }

    public static func makeShapeLayer(theme: MascotBalloonTheme = .clippy) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = theme.fillColor.cgColor
        layer.strokeColor = theme.strokeColor.cgColor
        layer.lineWidth = theme.borderWidth
        // Render crisp at the display's native resolution — the old 1x / no-antialias
        // setup left the rounded corners and tail jagged and blurry on Retina.
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        return layer
    }

    public static func path(size: CGSize, theme: MascotBalloonTheme = .clippy) -> CGPath {
        let inset: CGFloat = 0.5
        let left = inset, right = size.width - inset
        let bottom = theme.tailHeight, top = size.height - inset
        let r = theme.cornerRadius
        let tailLeftX = size.width * 0.5 - theme.tailHalfWidth
        let tailRightX = size.width * 0.5 + theme.tailHalfWidth
        let tipX = size.width * 0.5 + theme.tailTipOffset

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + r, y: bottom))
        path.addLine(to: CGPoint(x: tailLeftX, y: bottom))
        path.addLine(to: CGPoint(x: tipX, y: inset))
        path.addLine(to: CGPoint(x: tailRightX, y: bottom))
        path.addLine(to: CGPoint(x: right - r, y: bottom))
        path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right, y: bottom + r), radius: r)
        path.addLine(to: CGPoint(x: right, y: top - r))
        path.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right - r, y: top), radius: r)
        path.addLine(to: CGPoint(x: left + r, y: top))
        path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left, y: top - r), radius: r)
        path.addLine(to: CGPoint(x: left, y: bottom + r))
        path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left + r, y: bottom), radius: r)
        path.closeSubpath()
        return path
    }
}
