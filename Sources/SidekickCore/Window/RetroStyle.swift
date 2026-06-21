import AppKit
import CoreText

/// Authentic Windows 95 / Office-97 control palette and 3D bevel drawing, ported
/// from the documented Win32 system colors and the 98.css bevel recipes. Used to
/// give Sidekick's onboarding wizard, permission grants, and settings the period look.
/// (Win95-era `#C0C0C0` face — Office 97 shipped on Win95.)

private func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

public enum RetroPalette {
    public static let face = rgb(0xC0, 0xC0, 0xC0)          // 3DFACE — every dialog/button surface
    public static let highlight = rgb(0xFF, 0xFF, 0xFF)     // 3DHIGHLIGHT — brightest bevel edge
    public static let light = rgb(0xDF, 0xDF, 0xDF)         // 3DLIGHT — inner light bevel
    public static let shadow = rgb(0x80, 0x80, 0x80)        // 3DSHADOW — shadow bevel / gray text
    public static let darkShadow = rgb(0x0A, 0x0A, 0x0A)    // 3DDKSHADOW — darkest outer bevel (98.css)
    public static let windowBackground = face
    public static let fieldBackground = rgb(0xFF, 0xFF, 0xFF) // COLOR_WINDOW — editable interiors
    public static let frame = rgb(0x00, 0x00, 0x00)         // WINDOWFRAME — hard 1px outline
    public static let text = rgb(0x00, 0x00, 0x00)
    public static let grayText = shadow
    public static let titleBar = rgb(0x00, 0x00, 0x80)      // ACTIVECAPTION — navy
    public static let titleBarGradientEnd = rgb(0x10, 0x84, 0xD0) // GRADIENTACTIVECAPTION
    public static let captionText = rgb(0xFF, 0xFF, 0xFF)
    public static let selection = titleBar
    public static let desktopTeal = rgb(0x00, 0x80, 0x80)
    public static let infoBackground = rgb(0xFF, 0xFF, 0xE1) // INFOBK — tooltip pale yellow
}

public enum RetroBezelStyle {
    case raised   // default button / chip
    case sunken   // pressed button
    case field    // sunken editable well (text input, list)
    case window   // raised panel / dialog body
    case etched   // single engraved line (group box, divider)
}

public enum RetroBezel {
    /// Draws a Win9x double-bevel just inside `rect`. Assumes a flipped
    /// (top-left origin) coordinate space — see `RetroPanel` / `RetroButton`.
    public static func draw(_ style: RetroBezelStyle, in rect: NSRect) {
        switch style {
        case .raised: double(rect, RetroPalette.highlight, RetroPalette.darkShadow, RetroPalette.light, RetroPalette.shadow)
        case .sunken: double(rect, RetroPalette.darkShadow, RetroPalette.highlight, RetroPalette.shadow, RetroPalette.light)
        case .field:  double(rect, RetroPalette.shadow, RetroPalette.highlight, RetroPalette.darkShadow, RetroPalette.light)
        case .window: double(rect, RetroPalette.light, RetroPalette.darkShadow, RetroPalette.highlight, RetroPalette.shadow)
        case .etched: etched(rect)
        }
    }

    private static func double(_ r: NSRect, _ outerTL: NSColor, _ outerBR: NSColor, _ innerTL: NSColor, _ innerBR: NSColor) {
        ring(r, tl: outerTL, br: outerBR)
        ring(r.insetBy(dx: 1, dy: 1), tl: innerTL, br: innerBR)
    }

    /// Top + left edges in `tl`, bottom + right in `br`. 1pt, flipped coords (top = minY).
    private static func ring(_ r: NSRect, tl: NSColor, br: NSColor) {
        tl.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        br.setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }

    private static func etched(_ r: NSRect) {
        ring(r, tl: RetroPalette.shadow, br: RetroPalette.highlight)
    }
}

/// Period-correct UI font with graceful fallback. Prefers Microsoft Sans Serif /
/// Tahoma (present if the user has Office); falls back to the system font.
public enum RetroFont {
    /// Registers the bundled MS Sans Serif TTFs so the retro look ships with the app
    /// and doesn't depend on the user having the font installed. Safe to call at launch.
    public static func registerBundledFonts() {
        for url in bundledFontURLs() {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    public static func ui(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let names = bold
            ? ["MS Sans Serif Bold", "Microsoft Sans Serif", "Tahoma", "Geneva"]
            : ["MS Sans Serif", "Microsoft Sans Serif", "Tahoma", "Geneva"]
        for name in names {
            if let font = NSFont(name: name, size: size) {
                if bold && name != "MS Sans Serif Bold" {
                    return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                return font
            }
        }
        return .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    private static func bundledFontURLs() -> [URL] {
        let files = ["MSSansSerif.ttf", "MSSansSerif-Bold.ttf"]
        var dirs: [URL] = []
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appending(path: "Fonts"))
        }
        dirs.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "Resources/Fonts"))
        dirs.append(URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Fonts"))
        for dir in dirs {
            let urls = files.map { dir.appending(path: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !urls.isEmpty { return urls }
        }
        return []
    }
}

/// A flat Win9x panel: gray face with a raised double-bevel.
public final class RetroPanel: NSView {
    public var bezel: RetroBezelStyle = .window { didSet { needsDisplay = true } }
    public override var isFlipped: Bool { true }
    public override func draw(_ dirtyRect: NSRect) {
        RetroPalette.face.setFill()
        bounds.fill()
        RetroBezel.draw(bezel, in: bounds)
    }
}

/// A classic raised 3D pushbutton (75×23 by convention). Sinks on press, nudges
/// its label +1,+1, and draws the heavy black default-button ring when `isDefault`.
public final class RetroButton: NSView {
    public var title: String { didSet { needsDisplay = true } }
    public var onClick: (() -> Void)?
    public var isDefault = false { didSet { needsDisplay = true } }
    public var isEnabledButton = true { didSet { needsDisplay = true } }
    private var pressed = false

    public override var isFlipped: Bool { true }

    public init(title: String) {
        self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: 75, height: 23))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func draw(_ dirtyRect: NSRect) {
        RetroPalette.face.setFill()
        bounds.fill()
        var inner = bounds
        if isDefault {
            RetroPalette.frame.setFill()
            bounds.frame() // 1px black ring
            inner = bounds.insetBy(dx: 1, dy: 1)
        }
        RetroBezel.draw(pressed ? .sunken : .raised, in: inner)

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(11),
            .foregroundColor: isEnabledButton ? RetroPalette.text : RetroPalette.grayText,
            .paragraphStyle: para,
        ]
        let label = title as NSString
        let textSize = label.size(withAttributes: attrs)
        var textRect = NSRect(x: 0, y: (bounds.height - textSize.height) / 2, width: bounds.width, height: textSize.height)
        if pressed { textRect.origin.x += 1; textRect.origin.y += 1 }
        label.draw(in: textRect, withAttributes: attrs)
    }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabledButton else { return }
        pressed = true
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isEnabledButton else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != pressed { pressed = inside; needsDisplay = true }
    }

    public override func mouseUp(with event: NSEvent) {
        guard isEnabledButton else { return }
        let fire = pressed
        pressed = false
        needsDisplay = true
        if fire { onClick?() }
    }
}
