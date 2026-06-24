import ApplicationServices
import CoreGraphics
import Foundation

public struct DesktopAccessibilityTreeSnapshot: Equatable, Sendable {
    public struct Node: Equatable, Sendable {
        public let depth: Int
        public let role: String?
        public let subrole: String?
        public let roleDescription: String?
        public let title: String?
        public let label: String?
        public let value: String?
        public let identifier: String?
        public let focused: Bool?
        public let frame: CGRect?
        public let actions: [String]

        public init(
            depth: Int,
            role: String?,
            subrole: String?,
            roleDescription: String?,
            title: String?,
            label: String?,
            value: String?,
            identifier: String?,
            focused: Bool?,
            frame: CGRect?,
            actions: [String]
        ) {
            self.depth = depth
            self.role = role
            self.subrole = subrole
            self.roleDescription = roleDescription
            self.title = title
            self.label = label
            self.value = value
            self.identifier = identifier
            self.focused = focused
            self.frame = frame
            self.actions = actions
        }

        fileprivate var promptLine: String {
            var parts: [String] = []
            if let role {
                parts.append(role)
            } else {
                parts.append("AXElement")
            }
            if let subrole {
                parts.append("subrole=\(subrole)")
            }
            if let roleDescription {
                parts.append("roleDescription=\(roleDescription)")
            }
            if let title {
                parts.append("title=\(title)")
            }
            if let label {
                parts.append("label=\(label)")
            }
            if let value {
                parts.append("value=\(value)")
            }
            if let identifier {
                parts.append("identifier=\(identifier)")
            }
            if let focused {
                parts.append("focused=\(focused)")
            }
            if let frame {
                parts.append("frame=\(Self.format(frame))")
            }
            if actions.isEmpty == false {
                parts.append("actions=\(actions.joined(separator: ","))")
            }
            return parts.joined(separator: " | ")
        }

        private static func format(_ rect: CGRect) -> String {
            "x\(Int(rect.origin.x)) y\(Int(rect.origin.y)) w\(Int(rect.width)) h\(Int(rect.height))"
        }
    }

    public let appName: String?
    public let bundleIdentifier: String?
    public let processIdentifier: Int?
    public let nodes: [Node]
    public let issue: String?

    public init(
        appName: String?,
        bundleIdentifier: String?,
        processIdentifier: Int?,
        nodes: [Node],
        issue: String?
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.nodes = nodes
        self.issue = issue
    }

    public static func capture(
        desktopContext: DesktopContextSnapshot,
        maxNodes: Int = 120,
        maxDepth: Int = 8
    ) -> DesktopAccessibilityTreeSnapshot {
        guard let app = desktopContext.app else {
            return DesktopAccessibilityTreeSnapshot(
                appName: nil,
                bundleIdentifier: nil,
                processIdentifier: nil,
                nodes: [],
                issue: "active app unknown"
            )
        }
        guard AccessibilityPermission.isTrusted else {
            return DesktopAccessibilityTreeSnapshot(
                appName: app.name,
                bundleIdentifier: app.bundleIdentifier,
                processIdentifier: app.processIdentifier,
                nodes: [],
                issue: "accessibility permission missing"
            )
        }

        let appElement = AXUIElementCreateApplication(pid_t(app.processIdentifier))
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        let appWindows = windows(from: appElement)
        let roots = appWindows.isEmpty ? [appElement] : appWindows
        var nodes: [Node] = []
        for root in roots {
            collect(root, depth: 0, maxDepth: maxDepth, maxNodes: maxNodes, nodes: &nodes)
            guard nodes.count < maxNodes else { break }
        }

        return DesktopAccessibilityTreeSnapshot(
            appName: app.name,
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            nodes: nodes,
            issue: nodes.isEmpty ? "no accessibility nodes returned" : nil
        )
    }

    public var promptBlock: String {
        var lines = ["[Current accessibility tree snapshot captured before this turn:"]
        if let appName {
            let bundle = bundleIdentifier ?? "unknown bundle"
            let pid = processIdentifier.map(String.init) ?? "unknown"
            lines.append("- source app: \(appName) (\(bundle), pid \(pid))")
        } else {
            lines.append("- source app: unknown")
        }
        if let issue {
            lines.append("- issue: \(issue)")
        }
        lines.append("- captured AX nodes: \(nodes.count)")
        lines.append("- use this AX tree as the primary signal for UI text, unread/error states, controls, and available actions")
        lines.append("- do not require OCR for this check")
        for (index, node) in nodes.enumerated() {
            let indent = String(repeating: "  ", count: max(0, min(node.depth, 8)))
            lines.append("\(index + 1). \(indent)\(node.promptLine)")
        }
        lines.append("]")
        return lines.joined(separator: "\n")
    }

    private static func collect(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        maxNodes: Int,
        nodes: inout [Node]
    ) {
        guard nodes.count < maxNodes else { return }
        AXUIElementSetMessagingTimeout(element, 0.15)
        nodes.append(node(from: element, depth: depth))
        guard depth < maxDepth else { return }

        for child in children(from: element) {
            collect(child, depth: depth + 1, maxDepth: maxDepth, maxNodes: maxNodes, nodes: &nodes)
            guard nodes.count < maxNodes else { return }
        }
    }

    private static func node(from element: AXUIElement, depth: Int) -> Node {
        Node(
            depth: depth,
            role: stringValue(element, kAXRoleAttribute as CFString),
            subrole: stringValue(element, kAXSubroleAttribute as CFString),
            roleDescription: stringValue(element, kAXRoleDescriptionAttribute as CFString),
            title: stringValue(element, kAXTitleAttribute as CFString),
            label: stringValue(element, kAXDescriptionAttribute as CFString),
            value: stringValue(element, kAXValueAttribute as CFString),
            identifier: stringValue(element, kAXIdentifierAttribute as CFString),
            focused: boolValue(element, kAXFocusedAttribute as CFString),
            frame: frame(element),
            actions: actionNames(from: element)
        )
    }

    private static func windows(from appElement: AXUIElement) -> [AXUIElement] {
        guard let windows = copy(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
            return []
        }
        return windows
    }

    private static func children(from element: AXUIElement) -> [AXUIElement] {
        guard let children = copy(element, kAXChildrenAttribute as CFString) as? [AXUIElement] else {
            return []
        }
        return children
    }

    private static func actionNames(from element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let values = names as? [String] else {
            return []
        }
        return values.compactMap(clean)
    }

    private static func stringValue(_ element: AXUIElement, _ attribute: CFString) -> String? {
        guard let value = copy(element, attribute) else { return nil }
        if let string = value as? String {
            return clean(string)
        }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean)) ? "true" : "false"
        }
        if let number = value as? NSNumber {
            return clean(number.stringValue)
        }
        return nil
    }

    private static func boolValue(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        guard let value = copy(element, attribute) else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        return (value as? NSNumber)?.boolValue
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let point = pointValue(copy(element, kAXPositionAttribute as CFString)),
              let size = sizeValue(copy(element, kAXSizeAttribute as CFString)) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    private static func pointValue(_ value: CFTypeRef?) -> CGPoint? {
        guard let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeValue(_ value: CFTypeRef?) -> CGSize? {
        guard let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func copy(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static func clean(_ string: String?) -> String? {
        guard let string else { return nil }
        let trimmed = string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard trimmed.isEmpty == false else { return nil }
        return String(trimmed.prefix(240))
    }
}

extension DesktopAccessibilityTreeSnapshot {
    public func componentOutlineMarks(
        screen: DesktopContextSnapshot.ScreenInfo? = nil,
        limit: Int = 24
    ) -> [AnnotationMark] {
        componentOutlineFrames(screen: screen, limit: limit).map { .rectangle(frame: $0) }
    }

    public func componentOutlineFrames(
        screen: DesktopContextSnapshot.ScreenInfo? = nil,
        limit: Int = 24
    ) -> [CGRect] {
        guard limit > 0 else { return [] }
        let candidates = nodes.enumerated().compactMap { index, node -> ComponentOutlineCandidate? in
            guard let score = node.componentOutlineScore,
                  let rawFrame = node.frame?.standardized,
                  rawFrame.width >= 8,
                  rawFrame.height >= 8,
                  let appKitFrame = DesktopContextSnapshot.appKitFrame(forDisplayBounds: rawFrame, screen: screen)
            else {
                return nil
            }

            let clippedFrame: CGRect
            if let screen {
                let intersection = appKitFrame.standardized.intersection(screen.appKitFrame)
                guard intersection.isNull == false, intersection.width >= 8, intersection.height >= 8 else {
                    return nil
                }
                clippedFrame = intersection
                let screenArea = max(1, screen.appKitFrame.area)
                guard clippedFrame.area <= screenArea * 0.45 || node.focused == true else {
                    return nil
                }
            } else {
                clippedFrame = appKitFrame.standardized
            }

            return ComponentOutlineCandidate(
                index: index,
                frame: Self.pixelAligned(clippedFrame),
                score: score,
                area: clippedFrame.area
            )
        }

        var selected: [CGRect] = []
        for candidate in candidates.sorted(by: ComponentOutlineCandidate.precedes) {
            guard selected.contains(where: { Self.isDuplicate(candidate.frame, of: $0) }) == false else {
                continue
            }
            selected.append(candidate.frame)
            if selected.count >= limit {
                break
            }
        }
        return selected
    }

    private static func pixelAligned(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX.rounded(),
            y: rect.minY.rounded(),
            width: rect.width.rounded(),
            height: rect.height.rounded()
        )
    }

    private static func isDuplicate(_ lhs: CGRect, of rhs: CGRect) -> Bool {
        let intersection = lhs.intersection(rhs)
        guard intersection.isNull == false else { return false }
        let overlap = intersection.area / max(1, min(lhs.area, rhs.area))
        let sameSize = abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
        let sameOrigin = abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2
        return overlap > 0.92 || (sameSize && sameOrigin)
    }
}

private struct ComponentOutlineCandidate {
    let index: Int
    let frame: CGRect
    let score: Int
    let area: CGFloat

    static func precedes(_ lhs: ComponentOutlineCandidate, _ rhs: ComponentOutlineCandidate) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.area != rhs.area {
            return lhs.area < rhs.area
        }
        return lhs.index < rhs.index
    }
}

private enum ComponentOutlineHeuristics {
    static let primaryRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXComboBox",
        "AXTextField",
        "AXTextArea",
        "AXSearchField",
        "AXSlider",
        "AXLink",
        "AXMenuItem",
        "AXMenuButton",
        "AXTab",
        "AXDisclosureTriangle",
        "AXIncrementor",
        "AXColorWell",
        "AXSwitch",
    ]

    static let secondaryRoles: Set<String> = [
        "AXCell",
        "AXRow",
        "AXOutlineRow",
        "AXImage",
        "AXStaticText",
        "AXGroup",
    ]

    static let excludedRoles: Set<String> = [
        "AXApplication",
        "AXWindow",
        "AXSheet",
        "AXDrawer",
        "AXPopover",
        "AXMenuBar",
        "AXMenu",
        "AXToolbar",
        "AXScrollArea",
        "AXScrollBar",
        "AXSplitGroup",
    ]

    static let actionablePrefixes = [
        "AXPress",
        "AXConfirm",
        "AXPick",
        "AXShowMenu",
        "AXIncrement",
        "AXDecrement",
        "Name:",
    ]
}

private extension DesktopAccessibilityTreeSnapshot.Node {
    var componentOutlineScore: Int? {
        let role = role ?? ""
        guard ComponentOutlineHeuristics.excludedRoles.contains(role) == false else {
            return nil
        }

        let actionable = actions.contains { action in
            ComponentOutlineHeuristics.actionablePrefixes.contains { action.hasPrefix($0) }
        }
        let hasVisibleText = [title, label, value, identifier].contains { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        let focusedBoost = focused == true ? 60 : 0
        let roleDescription = (roleDescription ?? "").lowercased()
        let describedAsControl = [
            "button",
            "field",
            "link",
            "menu",
            "checkbox",
            "tab",
            "slider",
            "radio",
        ].contains { roleDescription.contains($0) }

        var score: Int
        if ComponentOutlineHeuristics.primaryRoles.contains(role) {
            score = 100
        } else if ComponentOutlineHeuristics.secondaryRoles.contains(role), actionable || focused == true || describedAsControl {
            score = 62
        } else if actionable {
            score = 55
        } else if focused == true {
            score = 50
        } else if describedAsControl {
            score = 45
        } else {
            return nil
        }

        if role == "AXStaticText", actionable == false, focused != true, describedAsControl == false {
            return nil
        }
        if hasVisibleText {
            score += 8
        }
        score += focusedBoost
        score += min(max(depth, 0), 8)
        return score
    }
}

private extension CGRect {
    var area: CGFloat {
        guard isNull == false else { return 0 }
        return max(0, width) * max(0, height)
    }
}
