import AppKit
import SidekickCore

@MainActor
struct RetroMenuItem {
    indirect enum Role {
        case action(icon: RetroMenuIcon? = nil)
        case toggle(isOn: Bool)
        case choice(isSelected: Bool)
        case submenu(items: [RetroMenuItem])
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

    static func choice(_ title: String, detail: String? = nil, isSelected: Bool, _ action: @escaping () -> Void) -> Self {
        RetroMenuItem(title: title, detail: detail, role: .choice(isSelected: isSelected), action: action)
    }

    static func submenu(_ title: String, detail: String? = nil, items: [RetroMenuItem]) -> Self {
        RetroMenuItem(title: title, detail: detail, role: .submenu(items: items), action: nil)
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
    private var windows: [RetroMenuWindow] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func show(items: [RetroMenuItem], topLeft point: NSPoint) {
        close()

        let panel = makePanel(items: items, topLeft: point, level: 0)
        windows = [panel]
        panel.orderFrontRegardless()
        panel.makeKey()
        installCloseMonitors()
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
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makePanel(items: [RetroMenuItem], topLeft point: NSPoint, level: Int) -> RetroMenuWindow {
        let content = RetroMenuView(
            items: items,
            level: level,
            dismiss: { [weak self] in
                self?.close()
            },
            openSubmenu: { [weak self] items, row, level in
                self?.openSubmenu(items: items, from: row, level: level)
            },
            closeSubmenus: { [weak self] level in
                self?.closeSubmenus(after: level)
            }
        )
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
        panel.level = WindowLevelPolicy.sidekickLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func openSubmenu(items: [RetroMenuItem], from row: NSView, level: Int) {
        closeSubmenus(after: level - 1)
        guard let rowWindow = row.window else { return }
        let rowRect = row.convert(row.bounds, to: nil)
        let screenRect = rowWindow.convertToScreen(rowRect)
        let point = NSPoint(x: screenRect.maxX - 2, y: screenRect.maxY)
        let panel = makePanel(items: items, topLeft: point, level: level)
        windows.append(panel)
        panel.orderFrontRegardless()
    }

    private func closeSubmenus(after level: Int) {
        guard windows.count > level + 1 else { return }
        let stale = windows.suffix(from: level + 1)
        stale.forEach { $0.orderOut(nil) }
        windows.removeLast(windows.count - level - 1)
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

    private func installCloseMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if event.type == .keyDown {
                if self?.handleKeyDown(event) == true {
                    return nil
                }
                return event
            }
            if
                event.type != .keyDown,
                let eventWindow = event.window,
                self?.windows.contains(where: { $0 === eventWindow }) == false
            {
                self?.close()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let menu = windows.last?.contentView as? RetroMenuView else {
            return false
        }
        switch event.keyCode {
        case 36, 49, 76:
            menu.activateSelectedRow()
            return true
        case 53:
            close()
            return true
        case 123:
            if windows.count > 1 {
                windows.last?.orderOut(nil)
                windows.removeLast()
            } else {
                close()
            }
            return true
        case 124:
            _ = menu.openSelectedSubmenu()
            return true
        case 125:
            menu.moveSelection(delta: 1)
            return true
        case 126:
            menu.moveSelection(delta: -1)
            return true
        default:
            return false
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
    private let level: Int
    private let dismiss: () -> Void
    private let openSubmenu: ([RetroMenuItem], NSView, Int) -> Void
    private let closeSubmenus: (Int) -> Void
    private var rows: [RetroMenuRowView] = []
    private var selectedRowIndex: Int?

    init(
        items: [RetroMenuItem],
        level: Int,
        dismiss: @escaping () -> Void,
        openSubmenu: @escaping ([RetroMenuItem], NSView, Int) -> Void,
        closeSubmenus: @escaping (Int) -> Void
    ) {
        self.items = items
        self.level = level
        self.dismiss = dismiss
        self.openSubmenu = openSubmenu
        self.closeSubmenus = closeSubmenus
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
            let row = RetroMenuRowView(
                item: item,
                level: level,
                dismiss: dismiss,
                openSubmenu: openSubmenu,
                closeSubmenus: closeSubmenus,
                selectRow: { [weak self] row in
                    self?.selectRow(row)
                }
            )
            row.frame = NSRect(x: Metrics.pad, y: y, width: bounds.width - Metrics.pad * 2, height: height)
            addSubview(row)
            rows.append(row)
            y += height
        }
    }

    func moveSelection(delta: Int) {
        let selectable = selectableRowIndices
        guard selectable.isEmpty == false else { return }
        let nextIndex: Int
        if let selectedRowIndex,
           let current = selectable.firstIndex(of: selectedRowIndex) {
            nextIndex = selectable[(current + delta + selectable.count) % selectable.count]
        } else {
            nextIndex = delta >= 0 ? selectable[0] : selectable[selectable.count - 1]
        }
        setSelectedRowIndex(nextIndex)
    }

    func activateSelectedRow() {
        guard let row = selectedOrDefaultRow() else { return }
        row.activate()
    }

    func openSelectedSubmenu() -> Bool {
        guard let row = selectedOrDefaultRow() else { return false }
        return row.openSubmenuIfAvailable()
    }

    private var selectableRowIndices: [Int] {
        rows.indices.filter { rows[$0].isSelectable }
    }

    private func selectRow(_ row: RetroMenuRowView) {
        guard let index = rows.firstIndex(where: { $0 === row }),
              rows[index].isSelectable
        else {
            return
        }
        setSelectedRowIndex(index)
    }

    private func selectedOrDefaultRow() -> RetroMenuRowView? {
        if let selectedRowIndex,
           rows.indices.contains(selectedRowIndex),
           rows[selectedRowIndex].isSelectable {
            return rows[selectedRowIndex]
        }
        guard let first = selectableRowIndices.first else {
            return nil
        }
        setSelectedRowIndex(first)
        return rows[first]
    }

    private func setSelectedRowIndex(_ index: Int) {
        selectedRowIndex = index
        for (rowIndex, row) in rows.enumerated() {
            row.isKeyboardSelected = rowIndex == index
        }
    }

    private static func height(for item: RetroMenuItem) -> CGFloat {
        switch item.role {
        case .header:
            return Metrics.headerHeight
        case .separator:
            return Metrics.separatorHeight
        case .action, .toggle, .choice, .submenu:
            return Metrics.rowHeight
        }
    }
}

private final class RetroMenuRowView: NSView {
    private let item: RetroMenuItem
    private let level: Int
    private let dismiss: () -> Void
    private let openSubmenu: ([RetroMenuItem], NSView, Int) -> Void
    private let closeSubmenus: (Int) -> Void
    private let selectRow: (RetroMenuRowView) -> Void
    private var isHovered = false
    private var tracking: NSTrackingArea?
    var isKeyboardSelected = false { didSet { needsDisplay = true } }

    init(
        item: RetroMenuItem,
        level: Int,
        dismiss: @escaping () -> Void,
        openSubmenu: @escaping ([RetroMenuItem], NSView, Int) -> Void,
        closeSubmenus: @escaping (Int) -> Void,
        selectRow: @escaping (RetroMenuRowView) -> Void
    ) {
        self.item = item
        self.level = level
        self.dismiss = dismiss
        self.openSubmenu = openSubmenu
        self.closeSubmenus = closeSubmenus
        self.selectRow = selectRow
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
        selectRow(self)
        needsDisplay = true
        if case .submenu(let items) = item.role {
            openSubmenu(items, self, level + 1)
        } else {
            closeSubmenus(level)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabledRow, bounds.contains(convert(event.locationInWindow, from: nil)) else {
            return
        }
        if case .submenu(let items) = item.role {
            openSubmenu(items, self, level + 1)
            return
        }
        dismiss()
        item.action?()
    }

    var isSelectable: Bool {
        isEnabledRow
    }

    func activate() {
        guard isEnabledRow else { return }
        if openSubmenuIfAvailable() {
            return
        }
        dismiss()
        item.action?()
    }

    func openSubmenuIfAvailable() -> Bool {
        guard case .submenu(let items) = item.role else {
            return false
        }
        openSubmenu(items, self, level + 1)
        return true
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
        case .submenu:
            drawRow(icon: nil, mark: nil, showsArrow: true)
        }
    }

    private var isEnabledRow: Bool {
        if case .submenu = item.role { return true }
        return item.action != nil
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

    private func drawRow(icon: RetroMenuIcon?, mark: String?, showsArrow: Bool = false) {
        let isHighlighted = isHovered || isKeyboardSelected
        if isHighlighted {
            RetroPalette.selection.setFill()
            bounds.fill()
        }

        let textColor = isHighlighted ? RetroPalette.captionText : RetroPalette.text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(11),
            .foregroundColor: textColor,
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(10),
            .foregroundColor: isHighlighted ? RetroPalette.captionText : RetroPalette.grayText,
        ]

        if let mark {
            (mark as NSString).draw(in: NSRect(x: 7, y: 4, width: 14, height: 14), withAttributes: attrs)
        } else if let icon {
            drawIcon(icon, color: textColor, rect: NSRect(x: 5, y: 4, width: 16, height: 14))
        }

        let arrowWidth: CGFloat = showsArrow ? 18 : 0
        let rightInset = CGFloat(8) + arrowWidth
        let detailWidth = detailColumnWidth(attributes: detailAttrs)
        let detailSpacing: CGFloat = detailWidth > 0 ? 6 : 0
        (item.title as NSString).draw(
            in: NSRect(
                x: 26,
                y: 4,
                width: max(20, bounds.width - 26 - rightInset - detailWidth - detailSpacing),
                height: 15
            ),
            withAttributes: attrs
        )
        if let detail = item.detail {
            let para = NSMutableParagraphStyle()
            para.alignment = .right
            var rightAttrs = detailAttrs
            rightAttrs[.paragraphStyle] = para
            (detail as NSString).draw(
                in: NSRect(x: bounds.width - rightInset - detailWidth, y: 5, width: detailWidth, height: 14),
                withAttributes: rightAttrs
            )
        }
        if showsArrow {
            drawArrow(color: textColor, rect: NSRect(x: bounds.width - 16, y: 6, width: 8, height: 10))
        }
    }

    private func detailColumnWidth(attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        guard let detail = item.detail else { return 0 }
        let measured = ceil((detail as NSString).size(withAttributes: attributes).width) + 8
        return min(max(74, measured), 128)
    }

    private func drawArrow(color: NSColor, rect: NSRect) {
        color.setFill()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: rect.minX, y: rect.minY))
        arrow.line(to: NSPoint(x: rect.maxX, y: rect.midY))
        arrow.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        arrow.close()
        arrow.fill()
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
