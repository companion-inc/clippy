import CoreGraphics
import Testing
@testable import ClippyCore

@Test func parsesTargetTagAndStripsItFromSpokenText() {
    let reply = "Click the add button to continue. [TARGET:120,210,40:add modifier]"
    let parsed = GroundingParser.parse(reply)
    #expect(parsed.spokenText == "Click the add button to continue.")
    #expect(parsed.tags == [.target(CGPoint(x: 120, y: 210), radius: 40, label: "add modifier", screen: nil)])
}

@Test func parsesPointNoneAsNoDirective() {
    let parsed = GroundingParser.parse("All set. [POINT:none]")
    #expect(parsed.tags.isEmpty)
    #expect(parsed.spokenText == "All set.")
}

@Test func streamingStripHidesTagsAndPartialTagsSoNoBracketFlashes() {
    // Complete tag removed.
    #expect(GroundingParser.stripForStreaming("Look up there [POINT:600,40:menu bar]") == "Look up there")
    // Half-typed tag hidden as it streams in (the bug: it used to flash).
    #expect(GroundingParser.stripForStreaming("Look up there [POIN") == "Look up there")
    #expect(GroundingParser.stripForStreaming("Look up there [POINT:600,40") == "Look up there")
    #expect(GroundingParser.stripForStreaming("Look up there [") == "Look up there")
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
    #expect(ScreenPointingDirection.screenRight.clippyAnimationName == "GestureLeft")
    #expect(ScreenPointingDirection.screenLeft.clippyAnimationName == "GestureRight")
    #expect(ScreenPointingDirection.screenUp.clippyAnimationName == "GestureUp")
    #expect(ScreenPointingDirection.screenDown.clippyAnimationName == "GestureDown")
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

@Test func picksScreenContainingClippyInsteadOfMainDisplay() {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let secondary = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
    let clippy = CGRect(x: -980, y: 600, width: 160, height: 160)

    #expect(ScreenPerception.bestScreenIndex(for: clippy, screenFrames: [main, secondary]) == 1)
}

@Test func picksScreenWithLargestClippyIntersectionWhenStraddlingDisplays() {
    let left = CGRect(x: -1200, y: 0, width: 1200, height: 900)
    let right = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let mostlyRight = CGRect(x: -30, y: 300, width: 160, height: 160)

    #expect(ScreenPerception.bestScreenIndex(for: mostlyRight, screenFrames: [left, right]) == 1)
}

@Test func picksNearestScreenForOffscreenClippyFrame() {
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let upper = CGRect(x: 0, y: 982, width: 1512, height: 982)
    let offscreenNearUpper = CGRect(x: 700, y: 2050, width: 160, height: 160)

    #expect(ScreenPerception.bestScreenIndex(for: offscreenNearUpper, screenFrames: [main, upper]) == 1)
}
