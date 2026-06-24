import CoreGraphics
import Testing
@testable import SidekickCore

@Test func parsesTargetTagAndStripsItFromSpokenText() {
    let reply = "Click the add button to continue. [TARGET:120,210,40:add modifier]"
    let parsed = GroundingParser.parse(reply)
    #expect(parsed.spokenText == "Click the add button to continue.")
    #expect(parsed.tags == [.target(CGPoint(x: 120, y: 210), radius: 40, label: "add modifier", screen: nil)])

    let angleReply = "<TARGET:942,695,38:Continue>Click the white Continue button right here."
    let angleParsed = GroundingParser.parse(angleReply)
    #expect(angleParsed.spokenText == "Click the white Continue button right here.")
    #expect(angleParsed.tags == [.target(CGPoint(x: 942, y: 695), radius: 38, label: "Continue", screen: nil)])
}

@Test func targetAndHoverCountAsRenderableVisualGuidance() {
    let tags: [GroundingTag] = [
        .point(CGPoint(x: 20, y: 30), label: "menu", screen: nil),
        .target(CGPoint(x: 120, y: 210), radius: 40, label: "add modifier", screen: nil),
        .hover(CGPoint(x: 80, y: 90), radius: 24, label: "menu", screen: nil),
        .act(animation: "Explain"),
    ]
    #expect(tags.map(\.isRenderableVisual) == [true, true, true, false])
}

@Test func pointTagCreatesSoftAttentionDot() {
    let mark = AnnotationMark(tag: .point(CGPoint(x: 120, y: 210), label: "menu", screen: nil))
    #expect(mark == .dot(center: CGPoint(x: 120, y: 210), progress: 1))
    #expect(mark?.visualBeatDuration == 0.22)
    #expect(mark?.withDrawProgress(0.5) == .dot(center: CGPoint(x: 120, y: 210), progress: 0.5))
}

@Test func parsesPointNoneAsNoDirective() {
    let parsed = GroundingParser.parse("All set. [POINT:none]")
    #expect(parsed.tags.isEmpty)
    #expect(parsed.spokenText == "All set.")
}

@Test func finalPointTagMatchesOnlyTrailingPointer() {
    #expect(GroundingParser.finalPointTag(in: "Look here. [POINT:10,20:menu]") == .point(
        CGPoint(x: 10, y: 20),
        label: "menu",
        screen: nil
    ))
    #expect(GroundingParser.finalPointTag(in: "Look here. [POINT:10,20:menu:screen2]") == .point(
        CGPoint(x: 10, y: 20),
        label: "menu",
        screen: 2
    ))
    #expect(GroundingParser.finalPointTag(in: "Look here. [POINT:none]") == nil)
    #expect(GroundingParser.finalPointTag(in: "[POINT:10,20:menu] then keep reading") == nil)
    #expect(GroundingParser.finalPointTag(in: "Draw this. [SHAPE:line:1,2;3,4:path]") == nil)
}

@Test func streamingStripHidesTagsAndPartialTagsSoNoBracketFlashes() {
    // Complete tag removed.
    #expect(GroundingParser.stripForStreaming("Look up there [POINT:600,40:menu bar]") == "Look up there")
    // Half-typed tag hidden as it streams in (the bug: it used to flash).
    #expect(GroundingParser.stripForStreaming("Look up there [POIN") == "Look up there")
    #expect(GroundingParser.stripForStreaming("Look up there [POINT:600,40") == "Look up there")
    #expect(GroundingParser.stripForStreaming("Look up there [") == "Look up there")
    #expect(GroundingParser.stripForStreaming("<TARGET:942,695,38:Continue>Click") == "Click")
    #expect(GroundingParser.stripForStreaming("<TARGET:942,695") == "")
    // A complete tag plus a half-typed one after it.
    #expect(GroundingParser.stripForStreaming("Hi [ACT:Wave] and [HOV") == "Hi and")
    // A non-tag bracket is left alone (not every "[" is a tag).
    #expect(GroundingParser.stripForStreaming("the array[0") == "the array[0")
}

@Test func parsesShapeWithScreenSuffix() {
    let parsed = GroundingParser.parse("Drag it across. [SHAPE:arrow:10,20;30,40:drag:screen2]")
    #expect(parsed.tags.count == 1)
    guard case let .shape(kind, points, label, screen)? = parsed.tags.first else {
        Issue.record("expected a shape directive")
        return
    }
    #expect(kind == .arrow)
    #expect(points == [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)])
    #expect(label == "drag")
    #expect(screen == 2)
}

@Test func parsesPolygonShapeForConstructiveAnnotations() {
    let parsed = GroundingParser.parse("[SHAPE:polygon:10,10;30,10;30,30;10,30:closed region]")
    #expect(parsed.tags.count == 1)
    guard case let .shape(kind, points, label, screen)? = parsed.tags.first else {
        Issue.record("expected a polygon directive")
        return
    }
    #expect(kind == .polygon)
    #expect(points == [
        CGPoint(x: 10, y: 10),
        CGPoint(x: 30, y: 10),
        CGPoint(x: 30, y: 30),
        CGPoint(x: 10, y: 30),
    ])
    #expect(label == "closed region")
    #expect(screen == nil)
}

@Test func annotationMarkPathCanBecomeASequencedVisualBeat() {
    let points = [
        CGPoint(x: 10, y: 10),
        CGPoint(x: 30, y: 10),
        CGPoint(x: 30, y: 30),
        CGPoint(x: 10, y: 30),
    ]
    let mark = AnnotationMark.path(points: points, shape: .polygon)
    #expect(mark.visualBeatDuration > 0)
    #expect(mark.withDrawProgress(0.5) == .partialPath(points: points, shape: .polygon, progress: 0.5))
}

@Test func windowAnchoredDrawingSceneReprojectsMarksWhenWindowMoves() {
    let anchor = DrawingWindowAnchor(
        ownerProcessIdentifier: 42,
        windowIdentifier: 7,
        ownerName: "TestApp",
        title: "Demo",
        browserURL: "https://example.com/demo",
        initialFrame: CGRect(x: 100, y: 200, width: 400, height: 300)
    )
    let mark = AnnotationMark.ring(center: CGPoint(x: 150, y: 260), radius: 24, kind: .target)
    let scene = DrawingScene(marks: [mark], anchor: .window(anchor))

    let moved = CGRect(x: 320, y: 480, width: 400, height: 300)
    #expect(scene.resolvedMarks(windowFrameProvider: { _ in moved }) == [
        .ring(center: CGPoint(x: 370, y: 540), radius: 24, kind: .target),
    ])
}

@Test func windowAnchoredDrawingSceneReprojectsRectanglesWhenWindowMoves() {
    let anchor = DrawingWindowAnchor(
        ownerProcessIdentifier: 42,
        windowIdentifier: 7,
        ownerName: "TestApp",
        title: "Demo",
        browserURL: nil,
        initialFrame: CGRect(x: 100, y: 200, width: 400, height: 300)
    )
    let mark = AnnotationMark.rectangle(frame: CGRect(x: 150, y: 260, width: 90, height: 34))
    let scene = DrawingScene(marks: [mark], anchor: .window(anchor))

    let moved = CGRect(x: 320, y: 480, width: 400, height: 300)
    #expect(scene.resolvedMarks(windowFrameProvider: { _ in moved }) == [
        .rectangle(frame: CGRect(x: 370, y: 540, width: 90, height: 34)),
    ])
    #expect(scene.primaryPoint(windowFrameProvider: { _ in moved }) == CGPoint(x: 415, y: 557))
}

@Test func windowAnchoredDrawingSceneReprojectsPointDotsWhenWindowMoves() {
    let anchor = DrawingWindowAnchor(
        ownerProcessIdentifier: 42,
        windowIdentifier: 7,
        ownerName: "TestApp",
        title: "Demo",
        browserURL: nil,
        initialFrame: CGRect(x: 100, y: 200, width: 400, height: 300)
    )
    let mark = AnnotationMark.dot(center: CGPoint(x: 150, y: 260), progress: 1)
    let scene = DrawingScene(marks: [mark], anchor: .window(anchor))
    let moved = CGRect(x: 320, y: 480, width: 400, height: 300)

    #expect(scene.resolvedMarks(windowFrameProvider: { _ in moved }) == [
        .dot(center: CGPoint(x: 370, y: 540), progress: 1),
    ])
    #expect(scene.withSequenceProgress(durations: [1], elapsed: 0.5)
        .resolvedMarks(windowFrameProvider: { _ in moved }) == [
            .dot(center: CGPoint(x: 370, y: 540), progress: 0.5),
        ])
}

@Test func windowAnchoredDrawingSceneKeepsPathGeometryLocalToWindow() {
    let anchor = DrawingWindowAnchor(
        ownerProcessIdentifier: 42,
        windowIdentifier: 7,
        ownerName: "TestApp",
        title: "Demo",
        browserURL: nil,
        initialFrame: CGRect(x: 100, y: 200, width: 400, height: 300)
    )
    let mark = AnnotationMark.path(
        points: [CGPoint(x: 120, y: 220), CGPoint(x: 180, y: 260)],
        shape: .arrow
    )
    let scene = DrawingScene(marks: [mark], anchor: .window(anchor))
    let moved = CGRect(x: -50, y: 90, width: 400, height: 300)

    #expect(scene.resolvedMarks(windowFrameProvider: { _ in moved }) == [
        .path(points: [CGPoint(x: -30, y: 110), CGPoint(x: 30, y: 150)], shape: .arrow),
    ])
}

@Test func windowAnchoredDrawingSceneIsWindowSpecific() {
    let anchor = DrawingWindowAnchor(
        ownerProcessIdentifier: 42,
        windowIdentifier: 7,
        ownerName: "TestApp",
        title: "Demo",
        browserURL: nil,
        initialFrame: CGRect(x: 100, y: 200, width: 400, height: 300)
    )
    let anchored = DrawingScene(
        marks: [.region(center: CGPoint(x: 120, y: 220), radius: 18)],
        anchor: .window(anchor)
    )
    let screenOnly = DrawingScene(marks: [
        .region(center: CGPoint(x: 120, y: 220), radius: 18),
    ])

    #expect(anchored.tracksMovingWindow)
    #expect(anchored.hidesWhenWindowIsNotFrontmost)
    #expect(screenOnly.hidesWhenWindowIsNotFrontmost == false)
}

@Test func userScreenAnnotationCanBeWindowSpecific() {
    let anchor = DrawingWindowAnchor(
        ownerProcessIdentifier: 42,
        windowIdentifier: 7,
        ownerName: "TestApp",
        title: "Demo",
        browserURL: nil,
        initialFrame: CGRect(x: 100, y: 200, width: 400, height: 300)
    )
    let annotation = UserScreenAnnotation(
        screenIndex: 0,
        screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        strokes: [[CGPoint(x: 120, y: 220), CGPoint(x: 180, y: 260)]],
        anchor: .window(anchor)
    )
    let moved = CGRect(x: -50, y: 90, width: 400, height: 300)

    #expect(annotation.scene.tracksMovingWindow)
    #expect(annotation.scene.hidesWhenWindowIsNotFrontmost)
    #expect(annotation.scene.resolvedPathPoints(windowFrameProvider: { _ in moved }) == [
        [CGPoint(x: -30, y: 110), CGPoint(x: 30, y: 150)],
    ])
}

@Test func appKitFrameConvertsCoreGraphicsWindowBoundsFromTopLeftDisplaySpace() {
    let window = DesktopContextSnapshot.WindowInfo(
        title: "Demo",
        ownerName: "TestApp",
        ownerProcessIdentifier: 42,
        windowIdentifier: 7,
        bounds: CGRect(x: 100, y: 50, width: 400, height: 300)
    )
    let screen = DesktopContextSnapshot.ScreenInfo(
        index: 0,
        appKitFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
        displayBounds: CGRect(x: 0, y: 0, width: 1000, height: 800),
        displayIdentifier: 1
    )

    #expect(DesktopContextSnapshot.appKitFrame(for: window, screen: screen)
        == CGRect(x: 100, y: 450, width: 400, height: 300))
}

@Test func accessibilityTreeComponentOutlinesConvertAXFramesToAppKitRectangles() {
    let screen = DesktopContextSnapshot.ScreenInfo(
        index: 0,
        appKitFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
        displayBounds: CGRect(x: 0, y: 0, width: 1_000, height: 800),
        displayIdentifier: 1
    )
    let tree = DesktopAccessibilityTreeSnapshot(
        appName: "Demo",
        bundleIdentifier: "com.example.demo",
        processIdentifier: 42,
        nodes: [
            .init(
                depth: 0,
                role: "AXWindow",
                subrole: nil,
                roleDescription: "standard window",
                title: "Demo",
                label: nil,
                value: nil,
                identifier: nil,
                focused: true,
                frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                actions: []
            ),
            .init(
                depth: 1,
                role: "AXButton",
                subrole: nil,
                roleDescription: "button",
                title: "Continue",
                label: nil,
                value: nil,
                identifier: "continue",
                focused: nil,
                frame: CGRect(x: 120, y: 50, width: 96, height: 32),
                actions: ["AXPress"]
            ),
            .init(
                depth: 1,
                role: "AXTextField",
                subrole: nil,
                roleDescription: "text field",
                title: nil,
                label: "Search",
                value: nil,
                identifier: "search",
                focused: true,
                frame: CGRect(x: 240, y: 700, width: 200, height: 36),
                actions: []
            ),
        ],
        issue: nil
    )

    let frames = tree.componentOutlineFrames(screen: screen, limit: 8)

    #expect(frames.contains(CGRect(x: 120, y: 718, width: 96, height: 32)))
    #expect(frames.contains(CGRect(x: 240, y: 64, width: 200, height: 36)))
    #expect(frames.contains(CGRect(x: 0, y: 0, width: 1_000, height: 800)) == false)
    #expect(tree.componentOutlineMarks(screen: screen, limit: 1).count == 1)
}

@Test func accessibilityTreeComponentOutlinesDeduplicateNestedControls() {
    let screen = DesktopContextSnapshot.ScreenInfo(
        index: 0,
        appKitFrame: CGRect(x: 0, y: 0, width: 900, height: 700),
        displayBounds: CGRect(x: 0, y: 0, width: 900, height: 700),
        displayIdentifier: 1
    )
    let tree = DesktopAccessibilityTreeSnapshot(
        appName: "Demo",
        bundleIdentifier: nil,
        processIdentifier: 42,
        nodes: [
            .init(
                depth: 1,
                role: "AXButton",
                subrole: nil,
                roleDescription: "button",
                title: "Save",
                label: nil,
                value: nil,
                identifier: nil,
                focused: nil,
                frame: CGRect(x: 300, y: 100, width: 90, height: 30),
                actions: ["AXPress"]
            ),
            .init(
                depth: 2,
                role: "AXStaticText",
                subrole: nil,
                roleDescription: "text",
                title: nil,
                label: "Save",
                value: nil,
                identifier: nil,
                focused: nil,
                frame: CGRect(x: 301, y: 101, width: 88, height: 28),
                actions: ["AXPress"]
            ),
        ],
        issue: nil
    )

    #expect(tree.componentOutlineFrames(screen: screen, limit: 8) == [
        CGRect(x: 300, y: 570, width: 90, height: 30),
    ])
}

@Test func keepsMultipleTagsInDocumentOrder() {
    let parsed = GroundingParser.parse("[POINT:5,5:one] then [HIGHLIGHT:9,9,3:two]")
    #expect(parsed.tags.count == 2)
    #expect(parsed.tags.first?.label == "one")
    #expect(parsed.tags.last?.label == "two")
}

@Test func parsesActAnimationTag() {
    let parsed = GroundingParser.parse("All set! [ACT:Congratulate]")
    #expect(parsed.spokenText == "All set!")
    #expect(parsed.tags == [.act(animation: "Congratulate")])
}

@Test func gesturePicksDirectionTowardTarget() {
    let center = CGPoint(x: 500, y: 300)
    #expect(GroundingDirector.screenDirection(from: center, to: CGPoint(x: 900, y: 305)) == .screenRight)
    #expect(GroundingDirector.screenDirection(from: center, to: CGPoint(x: 100, y: 305)) == .screenLeft)
    #expect(GroundingDirector.screenDirection(from: center, to: CGPoint(x: 505, y: 800)) == .screenUp)
    #expect(GroundingDirector.screenDirection(from: center, to: CGPoint(x: 505, y: 20)) == .screenDown)
    #expect(GroundingDirector.screenDirection(from: center, to: CGPoint(x: 505, y: 305)) == .attention)
}

@Test func gestureAnimationNamesMatchVisibleScreenDirection() {
    // The sprite pack's names are from Clippy's own perspective. In screen space,
    // GestureLeft is the frame where his arm points to the viewer's right, and
    // GestureRight points to the viewer's left.
    #expect(ScreenPointingDirection.screenRight.sidekickAnimationName == "GestureLeft")
    #expect(ScreenPointingDirection.screenLeft.sidekickAnimationName == "GestureRight")
    #expect(ScreenPointingDirection.screenUp.sidekickAnimationName == "GestureUp")
    #expect(ScreenPointingDirection.screenDown.sidekickAnimationName == "GestureDown")
}

@Test func pointingAnimationNameUsesScreenDirectionNotSpritePerspective() {
    let center = CGPoint(x: 500, y: 300)
    #expect(GroundingDirector.pointingAnimationName(from: center, to: CGPoint(x: 900, y: 305)) == "GestureLeft")
    #expect(GroundingDirector.pointingAnimationName(from: center, to: CGPoint(x: 100, y: 305)) == "GestureRight")
}

@Test func mapsScreenshotPixelToAppKitPoint() {
    let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let size = CGSize(width: 1920, height: 1080)
    #expect(GroundingDirector.screenPoint(fromPixel: CGPoint(x: 0, y: 0), imageSize: size, display: display)
        == CGPoint(x: 0, y: 1080))
    #expect(GroundingDirector.screenPoint(fromPixel: CGPoint(x: 1920, y: 1080), imageSize: size, display: display)
        == CGPoint(x: 1920, y: 0))
}

@Test func mapsScreenshotPixelsToCapturedScreenFrameNotCurrentScreen() {
    let capturedDisplay = CGRect(x: -395, y: 1117, width: 2560, height: 1440)
    let imageSize = CGSize(width: 1600, height: 900)
    let center = GroundingDirector.screenPoint(
        fromPixel: CGPoint(x: 800, y: 450),
        imageSize: imageSize,
        display: capturedDisplay
    )
    #expect(center == CGPoint(x: 885, y: 1837))
}

@Test func picksScreenContainingSidekickInsteadOfMainDisplay() {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let secondary = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
    let sidekick = CGRect(x: -980, y: 600, width: 160, height: 160)

    #expect(ScreenPerception.bestScreenIndex(for: sidekick, screenFrames: [main, secondary]) == 1)
}

@Test func picksScreenWithLargestSidekickIntersectionWhenStraddlingDisplays() {
    let left = CGRect(x: -1200, y: 0, width: 1200, height: 900)
    let right = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let mostlyRight = CGRect(x: -30, y: 300, width: 160, height: 160)

    #expect(ScreenPerception.bestScreenIndex(for: mostlyRight, screenFrames: [left, right]) == 1)
}

@Test func picksNearestScreenForOffscreenSidekickFrame() {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let upper = CGRect(x: 0, y: 982, width: 1512, height: 982)
    let offscreenNearUpper = CGRect(x: 700, y: 2050, width: 160, height: 160)

    #expect(ScreenPerception.bestScreenIndex(for: offscreenNearUpper, screenFrames: [main, upper]) == 1)
}
