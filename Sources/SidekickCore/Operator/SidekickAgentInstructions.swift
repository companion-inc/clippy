import Foundation

/// Sidekick's agent behavior contract for local desktop work. It keeps the
/// runtime-agnostic spine: the routing ladder, approval gates,
/// draft-then-verify, the snapshot-act-verify computer-use contract, macOS
/// permission-storm avoidance, and the screen pointing protocol.
///
/// This is appended to the local `claude`/`codex` system prompt by the brain.
public enum SidekickAgentInstructions {
    public struct ScreenshotPromptContext: Equatable, Sendable {
        public let path: String
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let screenNumber: Int
        public let isPrimary: Bool

        public init(
            path: String,
            pixelWidth: Int,
            pixelHeight: Int,
            screenNumber: Int,
            isPrimary: Bool
        ) {
            self.path = path
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.screenNumber = screenNumber
            self.isPrimary = isPrimary
        }
    }

    public static let systemPrompt = """
You are the local desktop assistant running inside the Sidekick macOS app.
Sidekick is the product shell; the active visible character is your spoken identity.
A held-key voice turn or a typed message starts a task; you reason, use local tools, and
reply with a short line the active character can show in its speech bubble and say aloud.

Everything runs locally. There is no cloud account, no billing, and no remote connectors.
Your tools are the local shell and file system, your own read/edit/run tools, and a local
computer-control bridge for driving other macOS apps. Keep commentary brief.

Routing — pick the narrowest capable route, in order:
1. Answer directly, or use local files / shell / CLI / web fetch for facts and data.
2. Use your own tools to read and edit files and run commands.
3. Use the computer-control bridge ONLY for last-mile native or browser GUI that no API or CLI can do.
An app being visible on screen is context, not an instruction to drive its GUI — prefer the
structured route unless the user explicitly says "click / type / use this window."

Workflow recording — when the user asks Sidekick to watch, record, learn, or turn a demo/video
into a reusable skill, use the event stream tools. Start recording only when the user is ready.
After recording starts, do not wait or poll; tell the user to perform the workflow and say done.
When they say they are done, stop the recording, read `session.json` and `events.jsonl` from the
returned paths, then create or refine a real discoverable skill folder. Use the recording as
evidence of the intended outcome, not as a coordinate-only macro. Omit sensitive captured values.

Approvals — stop and ask before anything irreversible or externally visible: purchases,
sends, deletes, payments, account changes, or overwriting the user's files. For messages and
email, draft first, show recipient + subject + body, and require explicit approval before
sending. A tool returning success is not proof — verify writes with a structured read-back
before you claim done.

Computer use — preserve the background contract: use `launch_app`, `list_windows`,
and `get_window_state`, act with the most specific tool by element or window-local screenshot
coordinate, then re-snapshot to verify the change landed; if nothing changed, say so rather
than assuming success. Never change the user's foreground app, never warp the real cursor,
and never use `open`, `osascript`, or Cmd-Tab to activate apps.
The computer-control cursor overlay is disabled in Sidekick. The visible pointer is the active
sidekick's body, plus Sidekick's own screen annotation marks.

Computer-control failures are Sidekick's problem to diagnose, not the user's setup chore. Do not
tell the user to start, connect, install, or run the bridge. First try the available local tools
and structured routes; when the GUI route is genuinely unavailable, say in one Sidekick-style
sentence that a local computer-control error happened and diagnostics were saved. Do not expose
internal names such as MCP, app-server, session, bridge, or capability in normal speech.

macOS permission prompts — Desktop, Documents, Downloads, iCloud, and Pictures each trigger a
separate OS prompt the user sees. Work in a non-protected working directory by default; touch
at most the single protected folder the task truly needs, deliberately and once. Never scan
multiple protected folders to "find" a file — ask for the path instead.

	Seeing the desktop — every turn includes current app/window metadata. Every turn also attempts
	to attach a fresh full-display screenshot as image context and includes the saved path plus
	pixel dimensions as the coordinate contract. Treat the attached screenshot as truth. If the
	image attachment is unavailable and only the path is present, Read that file before pointing,
	finding, or describing something on screen. Don't guess coordinates blind — if this turn has no
	screenshot note, use your local computer-control tools to inspect the app/window state before pointing or acting.

    Rich image answers — when the user explicitly asks to see images, examples, visual references,
    or sourced web results, Sidekick can show image cards in the bubble. Put each card in markdown
	as `![short caption](direct-image-url-or-local-file-path)` and include a nearby source link,
	such as `Source: [Site name](page-url)`. Keep the spoken answer short, cite the page the image
	came from, and use image cards only when seeing the image is the point of the answer.

	Screen annotations — when visible grounding makes the answer clearer, emit inline visual tags.
For [TARGET] and [HOVER], start the reply with exactly one tag. For [POINT], [HIGHLIGHT], and
[SHAPE], put the tag(s) at the end after the spoken text. Coordinates are integer pixels in the
screenshot you Read (top-left origin, x right, y down), not AppKit points. Use the right visual by intent:
[POINT:x,y:label] for showing one exact spot with the active sidekick's body plus a tiny precision dot.
[TARGET:x,y,r:label] only when the next visible step is one click/tap/focus/commit that Sidekick
can observe, recapture, and continue from. The spoken sentence must contain only that one action.
[HOVER:x,y,r:label] only for a hover reveal that Sidekick can observe and continue from.
[HIGHLIGHT:x,y,r:label] for a manual work area, such as a field, slider, canvas, or trim range.
[SHAPE:line|arrow|circle|curve|polygon:x1,y1;x2,y2;...:label] for drawn explanation, paths,
geometry, motion, and constructive diagrams.
For manual work Swift cannot reliably detect as complete, do not fake a [TARGET]. Use [HIGHLIGHT],
[POINT], and/or [SHAPE], tell the user what to do, and say how to resume, for example "When it
looks right, say continue." If no visual mark helps, omit visual tags.

Style — sound like the active sidekick: concise, helpful, a little retro, and never corporate or
robotic. Prefer doing over describing when the request is clear, keep commentary to brief
milestones, and if blocked name the user-visible missing permission or input without leaking
internal tool plumbing. Do not introduce yourself as "Sidekick"; if identity matters, use the
active character's display name from the [Active sidekick] block.
"""

    public static func systemPrompt(for spec: SidekickSpec) -> String {
        [
            systemPrompt,
            """
            [Active sidekick]
            Product name: Sidekick.
            Visible character: \(spec.displayName).
            \(spec.mannerPrompt)
            Speak as \(spec.displayName), not as the product name Sidekick.
            The character flavor changes wording and animation only; the desktop-assistant safety, brevity, and tool-use rules above always win.
            """,
        ].joined(separator: "\n\n")
    }

    /// Build the per-turn message for the brain: current desktop metadata, a
    /// fresh-screenshot note, an optional voice-context note, then the user's
    /// text. Voice in/out can change turn to turn, so this context is attached
    /// per message rather than baked into the static prompt above.
    public static func brainMessage(
        text: String,
        screenshotPath: String?,
        screenshotPixelWidth: Int,
        screenshotPixelHeight: Int,
        screenshots: [ScreenshotPromptContext] = [],
        inputMode: AssistantInputMode,
        speaking: Bool,
        desktopContext: DesktopContextSnapshot? = nil,
        requiresVisualGrounding: Bool = false,
        userAnnotationContext: String? = nil
    ) -> String {
        var blocks: [String] = []
        if let desktopContext {
            blocks.append(desktopContext.promptBlock)
        }
        if screenshots.isEmpty == false {
            blocks.append(contentsOf: screenshotPromptBlocks(screenshots))
        } else if let path = screenshotPath {
            blocks.append(screenshotPromptBlock(
                path: path,
                pixelWidth: screenshotPixelWidth,
                pixelHeight: screenshotPixelHeight
            ))
        }
        if let userAnnotationContext, !userAnnotationContext.isEmpty {
            blocks.append(userAnnotationContext)
        }
        if requiresVisualGrounding {
            blocks.append(visualGroundingTurnContract)
        }
        if let voice = voiceContextNote(inputMode: inputMode, speaking: speaking) {
            blocks.append(voice)
        }
        blocks.append(text)
        return blocks.joined(separator: "\n\n")
    }

    public static let visualGroundingTurnContract = """
    [Sidekick guided visual turn]
    The user is asking for visible screen grounding. Look at the current screenshot as truth, then choose the right Sidekick visual tag(s).
    Use [POINT:x,y:label] for one exact spot with the active sidekick's body plus a tiny precision dot. Use [TARGET:x,y,r:label] or [HOVER:x,y,r:label] only when the next visible step is a click/tap/focus/commit or hover reveal that Sidekick can observe, recapture, and continue from.
    If the next step is manual work Swift cannot reliably detect as complete, such as writing in a field, dragging a knob, adjusting a slider, choosing a color by taste, selecting a range, or trimming a clip, do not fake a target. Use [HIGHLIGHT] for the work area, [POINT] for the exact handle/control, and [SHAPE:arrow] or [SHAPE:curve] for the motion. Tell the user what to do and how to resume.
    Use [SHAPE:line|arrow|circle|curve|polygon:x1,y1;x2,y2;...:label] for drawn explanation, paths, geometry, motion, and constructive diagrams.
    Coordinates are integer pixels in the screenshot, top-left origin. Keep the spoken text short. Start [TARGET]/[HOVER] replies with exactly one tag; put [POINT]/[HIGHLIGHT]/[SHAPE] tags at the end. If no visual mark helps, omit visual tags.
    """

    public static func visualGroundingRepairMessage(
        originalUserText: String,
        previousAssistantText: String,
        screenshotPath: String?,
        screenshotPixelWidth: Int,
        screenshotPixelHeight: Int,
        screenshots: [ScreenshotPromptContext] = [],
        desktopContext: DesktopContextSnapshot?
    ) -> String {
        var blocks: [String] = []
        if let desktopContext {
            blocks.append(desktopContext.promptBlock)
        }
        if screenshots.isEmpty == false {
            blocks.append(contentsOf: screenshotPromptBlocks(screenshots))
        } else if let screenshotPath {
            blocks.append(screenshotPromptBlock(
                path: screenshotPath,
                pixelWidth: screenshotPixelWidth,
                pixelHeight: screenshotPixelHeight
            ))
        }
        blocks.append(visualGroundingTurnContract)
        blocks.append("""
        [Visual grounding repair]
        The previous assistant response for this same user request had no renderable visual grounding tag, so Sidekick could not mark the screen.
        Original user request:
        \(originalUserText)

        Previous assistant response:
        \(previousAssistantText)

        Now produce the corrected final response. Read the screenshot path above and derive useful visual tag(s) from that image: [POINT] for one spot, [TARGET]/[HOVER] for an observable guided step, [HIGHLIGHT] for a manual work area, or [SHAPE] for drawn explanation. Keep the spoken text short. If no visual mark helps, omit visual tags.
        """)
        return blocks.joined(separator: "\n\n")
    }

    public static func guidedTargetFollowUpMessage(
        label: String,
        trigger: String,
        triggerPointX: Int,
        triggerPointY: Int,
        round: Int,
        remainingRounds: Int,
        overallGoal: String,
        previousInstruction: String,
        completedSteps: [String],
        screenshotPath: String?,
        screenshotPixelWidth: Int,
        screenshotPixelHeight: Int,
        screenshots: [ScreenshotPromptContext] = [],
        desktopContext: DesktopContextSnapshot?
    ) -> String {
        var blocks: [String] = []
        if let desktopContext {
            blocks.append(desktopContext.promptBlock)
        }
        if screenshots.isEmpty == false {
            blocks.append(contentsOf: screenshotPromptBlocks(screenshots))
        } else if let screenshotPath {
            blocks.append(screenshotPromptBlock(
                path: screenshotPath,
                pixelWidth: screenshotPixelWidth,
                pixelHeight: screenshotPixelHeight
            ))
        }
        blocks.append("""
        [Guided target follow-up]
        Overall user goal:
        \(overallGoal)

        Previous instruction:
        \(previousInstruction)

        Completed guided steps:
        \(completedSteps.isEmpty ? "none yet" : completedSteps.joined(separator: "\n"))

        The user \(trigger) the guided target "\(label)" at AppKit screen point (\(triggerPointX), \(triggerPointY)). This is click-to-advance round \(round); remaining click-to-advance turns after this response: \(remainingRounds).
        Look at the fresh screenshot above as truth. Treat "\(label)" as completed unless the screen clearly proves it did not work. Continue toward the overall user goal; do not restart a generic tour and do not ask the user to repeat completed steps.
        If the new screenshot looks like the same state because the previous target opened a menu, revealed a submenu, or toggled a panel, do not re-emit that same opener. Move to the next nested item that actually commits the action, or finish.
        Choose the right visual by intent. Use exactly one tag-first [TARGET:x,y,r:label] or [HOVER:x,y,r:label] only when the next visible step is a click/tap/focus/commit or hover reveal that Sidekick can observe, recapture, and continue from. The TARGET sentence must contain only that one immediate action; never combine "click this, then drag, then pick..." into one target.
        If the next step is manual work Swift cannot reliably detect as complete, such as writing in a visible field, dragging a knob, adjusting a slider, choosing a color by taste, selecting a range, or trimming a clip, do not fake a target. Use [HIGHLIGHT] for the work area, [POINT] for the exact handle/control, and [SHAPE:arrow] or [SHAPE:curve] for the motion. Tell the user what to do and how to resume, for example "When it looks right, say continue."
        If the task is complete, answer with one short completion sentence and no visual tag. Never say "keep going" or "do it" without a distinct next visible instruction. Do not emit [POINT:none]. You have \(remainingRounds) remaining click-to-advance turns after this response. If that number is 0, do not emit [TARGET].
        """)
        return blocks.joined(separator: "\n\n")
    }

    private static func screenshotPromptBlocks(_ screenshots: [ScreenshotPromptContext]) -> [String] {
        screenshots.map { screenshot in
            screenshotPromptBlock(
                path: screenshot.path,
                pixelWidth: screenshot.pixelWidth,
                pixelHeight: screenshot.pixelHeight,
                screenNumber: screenshot.screenNumber,
                isPrimary: screenshot.isPrimary
            )
        }
    }

    private static func screenshotPromptBlock(path: String, pixelWidth: Int, pixelHeight: Int) -> String {
        """
        [Current full-display screenshot of the user's screen: \(path) (\(pixelWidth)x\(pixelHeight) px). \
        This screenshot is attached to the turn when the brain supports local images; the path is \
        also available as a fallback. Any visual coordinate \
        you emit MUST be real pixel coordinates in THAT image (top-left origin), not normalized \
        0-1000 coordinates and not macOS/AppKit screen points.]
        """
    }

    private static func screenshotPromptBlock(
        path: String,
        pixelWidth: Int,
        pixelHeight: Int,
        screenNumber: Int,
        isPrimary: Bool
    ) -> String {
        let primaryNote = isPrimary ? " primary focus" : ""
        let suffixNote = isPrimary
            ? "Use unsuffixed visual tags for this primary focus screen."
            : "To mark this screen, append :screen\(screenNumber), e.g. [POINT:x,y:label:screen\(screenNumber)] or [SHAPE:arrow:x1,y1;x2,y2:label:screen\(screenNumber)]."
        return """
        [Current full-display screenshot screen\(screenNumber)\(primaryNote): \(path) (\(pixelWidth)x\(pixelHeight) px). \
        This screenshot is attached to the turn when the brain supports local images; the path is \
        also available as a fallback. \(suffixNote) Any coordinate you emit MUST be real pixel \
        coordinates in THIS image (top-left origin), not normalized 0-1000 coordinates and not \
        macOS/AppKit screen points.]
        """
    }

    /// Current product policy is to give every turn eyes. The capture remains
    /// behind one function so tests and callers agree on the privacy/perf trade.
    public static func shouldAttachScreenshot(
        text _: String,
        inputMode _: AssistantInputMode,
        desktopContext _: DesktopContextSnapshot? = nil
    ) -> Bool {
        true
    }

    public static func shouldShareDesktopContext(
        text _: String,
        inputMode _: AssistantInputMode,
        desktopContext _: DesktopContextSnapshot?
    ) -> Bool {
        true
    }

    /// Turns that need MCP tools use the Codex app-server lane. Visual grounding
    /// remains a normal model reply because every turn already carries screenshot
    /// context and Sidekick acts on inline visual tags from any brain.
    public static func shouldUseCodexToolLane(
        text: String,
        inputMode: AssistantInputMode
    ) -> Bool {
        shouldUseComputerControl(text: text, inputMode: inputMode)
            || shouldUseRecordReplayTool(text: text, inputMode: inputMode)
    }

    public static func shouldUseRecordReplayTool(
        text: String,
        inputMode _: AssistantInputMode
    ) -> Bool {
        let lower = text.lowercased()
        let phrases = [
            "record my workflow",
            "record this workflow",
            "record what i'm doing",
            "record what i am doing",
            "watch me",
            "learn this workflow",
            "turn this into a skill",
            "turn it into a skill",
            "create a skill from",
            "make a skill from",
            "skill from this",
            "skill from a video",
            "create a skill",
            "make a skill",
        ]
        if phrases.contains(where: lower.contains) {
            return true
        }
        let words = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let wordSet = Set(words)
        let recordWords = Set(["record", "watch", "learn", "capture", "demo", "video"])
        let skillWords = Set(["skill", "workflow", "automation", "replay"])
        return !wordSet.isDisjoint(with: recordWords) && !wordSet.isDisjoint(with: skillWords)
    }

    /// Turns that ask Sidekick to point at or draw on the visible screen can be
    /// answered by the selected model using inline visual tags.
    public static func shouldUseScreenAnnotationTool(
        text: String,
        inputMode: AssistantInputMode
    ) -> Bool {
        let lower = text.lowercased()
        if shouldUseGuidedTargetGrounding(text: text) {
            return true
        }
        let words = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let wordSet = Set(words)

        let directVisualActions = Set(["annotate", "annotation", "highlight", "circle", "outline"])
        if !wordSet.isDisjoint(with: directVisualActions) {
            return true
        }

        let screenReferences = Set([
            "screen", "page", "window", "video", "image", "picture", "this", "that",
            "here", "there", "it", "menu", "button", "control", "target", "route",
            "diagram", "triangle", "square", "squares", "area", "areas", "field",
            "form",
        ])
        let drawWords = Set(["draw", "drawing", "drawn"])
        if !wordSet.isDisjoint(with: drawWords), !wordSet.isDisjoint(with: screenReferences) {
            return true
        }

        let pointingActions = Set(["point", "mark"])
        if !wordSet.isDisjoint(with: pointingActions), !wordSet.isDisjoint(with: screenReferences) {
            return true
        }

        if lower.contains("show me where") || lower.contains("show where") || lower.contains("call out") {
            return true
        }

        if inputMode == .voice, words.count <= 10 {
            let actionWords = Set(["annotate", "draw", "highlight", "circle", "outline", "point", "mark", "arrow"])
            if words.contains(where: actionWords.contains) { return true }
        }
        return false
    }

    /// Turns that ask Sidekick to drive a native app or browser need the Codex app-server
    /// lane because that is where the computer-control MCP server is wired.
    public static func shouldUseComputerControl(
        text: String,
        inputMode: AssistantInputMode
    ) -> Bool {
        let lower = text.lowercased()
        if shouldUseGuidedTargetGrounding(text: text) {
            return false
        }
        let passiveVisualGrounding = shouldUsePassiveVisualGrounding(text: text, inputMode: inputMode)
        let controlPhrases = [
            "click",
            "double click",
            "right click",
            "type into",
            "type in",
            "fill in",
            "fill it",
            "fill out",
            "fill the",
            "fill this",
            "complete the form",
            "complete this form",
            "apply for",
            "apply to",
            "submit",
            "press",
            "select",
            "choose",
            "scroll",
            "drag",
            "hover over",
            "hover on",
            "use this window",
            "use the window",
            "use this page",
            "use the page",
            "use the browser",
            "drive the browser",
            "application form",
            "the form",
            "this form",
        ]
        if passiveVisualGrounding {
            if containsNoClickActionPhrase(lower) {
                return false
            }
            let activeControlPhrases = controlPhrases.filter {
                $0 != "submit" && $0 != "application form" && $0 != "the form" && $0 != "this form"
            }
            if activeControlPhrases.contains(where: { lower.contains($0) }) {
                return true
            }
            return false
        }
        if controlPhrases.contains(where: { lower.contains($0) }) {
            return true
        }

        let words = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if inputMode == .voice, words.count <= 10 {
            let actionWords = Set(["click", "type", "fill", "submit", "press", "select", "choose", "scroll", "drag"])
            if words.contains(where: actionWords.contains) { return true }
        }
        return false
    }

    private static func containsNoClickActionPhrase(_ lower: String) -> Bool {
        let actionPhrases = [
            "do not click",
            "don't click",
            "do not press",
            "don't press",
            "without clicking",
            "without pressing",
            "no clicking",
            "no click",
        ]
        return actionPhrases.contains { lower.contains($0) }
    }

    private static func shouldUsePassiveVisualGrounding(
        text: String,
        inputMode: AssistantInputMode
    ) -> Bool {
        let lower = text.lowercased()
        let words = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let wordSet = Set(words)
        let passiveVisualActions = Set([
            "annotate", "annotation", "highlight", "circle", "outline",
            "point", "mark", "show", "draw", "drawing", "drawn",
        ])
        guard !wordSet.isDisjoint(with: passiveVisualActions)
                || lower.contains("show me where")
                || lower.contains("show where")
                || lower.contains("call out") else {
            return false
        }
        if containsNoClickActionPhrase(lower) {
            return true
        }
        return shouldUseScreenAnnotationTool(text: text, inputMode: inputMode)
    }

    private static func shouldUseGuidedTargetGrounding(text: String) -> Bool {
        let lower = text.lowercased()
        let hasClick = lower.contains("click") || lower.contains("press") || lower.contains("tap")
        guard hasClick else { return false }
        let guidancePhrases = [
            "guide me",
            "show me where",
            "show where",
            "where to click",
            "where should i click",
            "mark the click target",
            "mark it as the click target",
            "mark as the click target",
            "click target",
            "continue after i click",
            "continue after my click",
            "after i click it",
            "walk me through",
        ]
        return guidancePhrases.contains { lower.contains($0) }
    }

    /// A per-turn note telling the model how this turn arrives and leaves. Spoken input was
    /// transcribed (read for intent past speech-to-text slips); spoken output is read aloud
    /// (write for the ear). Returns nil for a plain typed, bubble-only turn.
    public static func voiceContextNote(inputMode: AssistantInputMode, speaking: Bool) -> String? {
        var parts: [String] = []
        if inputMode == .voice {
            parts.append("The user SPOKE this and it was transcribed by speech-to-text, so "
                + "expect slips — homophones, wrong word boundaries, dropped small words, missing "
                + "punctuation or capitals. Read for what they MEANT, not the literal characters; "
                + "if a word looks wrong, infer it from context instead of answering the typo.")
        }
        if speaking {
            parts.append("Your reply is read aloud by text-to-speech, so write for the ear: one or "
                + "two short, natural, spoken-sounding sentences. No markdown, bullet lists, code "
                + "blocks, file paths, URLs, API keys, or internal tool names — they sound wrong spoken. "
                + "Only use markdown image cards and source links when the user explicitly asks to see images or sourced visual examples; those cards are hidden from speech. "
                + "Use a Sidekick voice: bright, compact, helpful, gently retro, and not robotic. "
                + VoiceSpeechTags.instruction + " Trailing visual tags are fine; "
                + "they are stripped before speaking.")
        }
        guard !parts.isEmpty else { return nil }
        return "[Voice mode — " + parts.joined(separator: " ") + "]"
    }
}
