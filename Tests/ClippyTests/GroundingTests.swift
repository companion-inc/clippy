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
    #expect(GroundingDirector.gesture(from: center, to: CGPoint(x: 900, y: 305)) == .right)
    #expect(GroundingDirector.gesture(from: center, to: CGPoint(x: 100, y: 305)) == .left)
    #expect(GroundingDirector.gesture(from: center, to: CGPoint(x: 505, y: 800)) == .up)
    #expect(GroundingDirector.gesture(from: center, to: CGPoint(x: 505, y: 20)) == .down)
    #expect(GroundingDirector.gesture(from: center, to: CGPoint(x: 505, y: 305)) == .attention)
}

@Test func mapsScreenshotPixelToAppKitPoint() {
    let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let size = CGSize(width: 1920, height: 1080)
    #expect(GroundingDirector.screenPoint(fromPixel: CGPoint(x: 0, y: 0), imageSize: size, display: display)
        == CGPoint(x: 0, y: 1080))
    #expect(GroundingDirector.screenPoint(fromPixel: CGPoint(x: 1920, y: 1080), imageSize: size, display: display)
        == CGPoint(x: 1920, y: 0))
}
