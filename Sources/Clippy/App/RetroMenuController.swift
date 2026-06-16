import AppKit
import ClippyCore

@MainActor
struct RetroMenuItem {
    enum Role {
        case action(icon: RetroMenuIcon? = nil)
        case toggle(isOn: Bool)
        case choice(isSelected: Bool)
        case header
        case separator
    }

    let title: String
    let detail: String?
    let role: Role
    let action: (() -> Void)?

    static func action(_ title: String, detail: String? = nil, icon: RetroMenuIcon? = nil, _ action: @escaping () -> Void) -> Self {
        RetroMenuItem(title: title, detail: detail, role: .action(icon: icon), action: action)
    }

    static func toggle(_ title: String, isOn: Bool, _ action: @escaping () -> Void) -> Self {
        RetroMenuItem(title: title, detail: nil, role: .toggle(isOn: isOn), action: action)
    }

    static func choice(_ title: String, isSelected: Bool, _ action: @escaping () -> Void) -> Self {
        RetroMenuItem(title: title, detail: nil, role: .choice(isSelected: isSelected), action: action)
    }

    static func header(_ title: String) -> Self {
        RetroMenuItem(title: title, detail: nil, role: .header, action: nil)
    }

    static func separator() -> Self {
        RetroMenuItem(title: "", detail: nil, role: .separator, action: nil)
    }
}

enum RetroMenuIcon {
    case eye
    case eyeSlash
}

@MainActor
final class RetroMenuController {
    private var window: RetroMenuWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func show(items: [RetroMenuItem], topLeft point: NSPoint) {
        close()

        let content = RetroMenuView(items: items, dismiss: { [weak self] in
            self?.close()
        })
        let origin = adjustedOrigin(forTopLeft: point, size: content.frame.size)
        let panel = RetroMenuWindow(
            contentRect: NSRect(origin: origin, size: content.frame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = content
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = WindowLevelPolicy.clippyLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.orderFrontRegardless()
        panel.makeKey()
        window = panel
        installCloseMonitors(for: panel)
    }

    func close() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }

    private func adjustedOrigin(forTopLeft point: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = (screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800))
            .insetBy(dx: 6, dy: 6)

        let x = min(max(point.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        var top = min(max(point.y, visible.minY + size.height), visible.maxY)
        if top - size.height < visible.minY {
            top = visible.minY + size.height
        }
        return NSPoint(x: x, y: top - size.height)
    }

    private func installCloseMonitors(for panel: NSWindow) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak panel] event in
            if event.type == .keyDown, event.keyCode == 53 {
                self?.close()
                return nil
            }
            if let panel, event.window !== panel, event.type != .keyDown {
                self?.close()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }
}

private final class RetroMenuWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class RetroMenuView: NSView {
    private enum Metrics {
        static let width: CGFloat = 318
        static let pad: CGFloat = 4
        static let rowHeight: CGFloat = 22
        static let headerHeight: CGFloat = 18
        static let separatorHeight: CGFloat = 8
    }

    private let items: [RetroMenuItem]
    private let dismiss: () -> Void

    init(items: [RetroMenuItem], dismiss: @escaping () -> Void) {
        self.items = items
        self.dismiss = dismiss
        let height = items.reduce(Metrics.pad * 2) { total, item in
            total + Self.height(for: item)
        }
        super.init(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: height))
        buildRows()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        RetroPalette.face.setFill()
        bounds.fill()
        RetroBezel.draw(.window, in: bounds)
    }

    private func buildRows() {
        var y = Metrics.pad
        for item in items {
            let height = Self.height(for: item)
            let row = RetroMenuRowView(item: item, dismiss: dismiss)
            row.frame = NSRect(x: Metrics.pad, y: y, width: bounds.width - Metrics.pad * 2, height: height)
            addSubview(row)
            y += height
        }
    }

    private static func height(for item: RetroMenuItem) -> CGFloat {
        switch item.role {
        case .header:
            return Metrics.headerHeight
        case .separator:
            return Metrics.separatorHeight
        case .action, .toggle, .choice:
            return Metrics.rowHeight
        }
    }
}

private final class RetroMenuRowView: NSView {
    private let item: RetroMenuItem
    private let dismiss: () -> Void
    private var isHovered = false
    private var tracking: NSTrackingArea?

    init(item: RetroMenuItem, dismiss: @escaping () -> Void) {
        self.item = item
        self.dismiss = dismiss
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        if let tracking {
            removeTrackingArea(tracking)
        }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        tracking = next
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabledRow else { return }
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabledRow, bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return
        }
        dismiss()
        item.action?()
    }

    override func draw(_ dirtyRect: NSRect) {
        switch item.role {
        case .separator:
            drawSeparator()
        case .header:
            drawHeader()
        case .action(let icon):
            drawRow(icon: icon, mark: nil)
        case .toggle(let isOn):
            drawRow(icon: nil, mark: isOn ? "✓" : nil)
        case .choice(let isSelected):
            drawRow(icon: nil, mark: isSelected ? "•" : nil)
        }
    }

    private var isEnabledRow: Bool {
        item.action != nil
    }

    private func drawSeparator() {
        RetroBezel.draw(.etched, in: NSRect(x: 24, y: 3, width: bounds.width - 30, height: 2))
    }

    private func drawHeader() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(10, bold: true),
            .foregroundColor: RetroPalette.grayText,
        ]
        (item.title as NSString).draw(in: NSRect(x: 8, y: 3, width: bounds.width - 16, height: 14), withAttributes: attrs)
    }

    private func drawRow(icon: RetroMenuIcon?, mark: String?) {
        if isHovered {
            RetroPalette.selection.setFill()
            bounds.fill()
        }

        let textColor = isHovered ? RetroPalette.captionText : RetroPalette.text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(11),
            .foregroundColor: textColor,
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(10),
            .foregroundColor: isHovered ? RetroPalette.captionText : RetroPalette.grayText,
        ]

        if let mark {
            (mark as NSString).draw(in: NSRect(x: 7, y: 4, width: 14, height: 14), withAttributes: attrs)
        } else if let icon {
            drawIcon(icon, color: textColor, rect: NSRect(x: 5, y: 4, width: 16, height: 14))
        }

        let detailWidth: CGFloat = item.detail == nil ? 0 : 64
        (item.title as NSString).draw(
            in: NSRect(x: 26, y: 4, width: bounds.width - 34 - detailWidth, height: 15),
            withAttributes: attrs
        )
        if let detail = item.detail {
            let para = NSMutableParagraphStyle()
            para.alignment = .right
            var rightAttrs = detailAttrs
            rightAttrs[.paragraphStyle] = para
            (detail as NSString).draw(
                in: NSRect(x: bounds.width - detailWidth - 8, y: 5, width: detailWidth, height: 14),
                withAttributes: rightAttrs
            )
        }
    }

    private func drawIcon(_ icon: RetroMenuIcon, color: NSColor, rect: NSRect) {
        color.setStroke()
        color.setFill()
        let eye = NSBezierPath()
        eye.move(to: NSPoint(x: rect.minX + 1, y: rect.midY))
        eye.curve(
            to: NSPoint(x: rect.maxX - 1, y: rect.midY),
            controlPoint1: NSPoint(x: rect.minX + 5, y: rect.minY + 1),
            controlPoint2: NSPoint(x: rect.maxX - 5, y: rect.minY + 1)
        )
        eye.curve(
            to: NSPoint(x: rect.minX + 1, y: rect.midY),
            controlPoint1: NSPoint(x: rect.maxX - 5, y: rect.maxY - 1),
            controlPoint2: NSPoint(x: rect.minX + 5, y: rect.maxY - 1)
        )
        eye.lineWidth = 1
        eye.stroke()
        NSBezierPath(ovalIn: NSRect(x: rect.midX - 2, y: rect.midY - 2, width: 4, height: 4)).fill()
        if icon == .eyeSlash {
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 2, y: rect.maxY - 1))
            slash.line(to: NSPoint(x: rect.maxX - 2, y: rect.minY + 1))
            slash.lineWidth = 2
            slash.stroke()
        }
    }
}
