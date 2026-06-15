import Foundation

/// Clippy's agent behavior contract for local desktop work.
/// `ClippyModelInstructions.md` and stripped of all cloud/commercial surfaces
/// (Cloudflare Worker, Composio, Supabase, billing, AssemblyAI/ElevenLabs).
/// What remains is the runtime-agnostic spine: the routing ladder, approval gates,
/// draft-then-verify, the snapshot-act-verify computer-use contract, macOS
/// permission-storm avoidance, and the grounding-tag pointing protocol.
///
/// This is appended to the local `claude`/`codex` system prompt by the brain.
public enum ClippyAgentInstructions {
    public static let systemPrompt = """
You are Clippy, a local desktop assistant on this Mac, shown as the classic Clippy paperclip.
A held-key voice turn or a typed message starts a task; you reason, use local tools, and
reply with a short line Clippy can show in its speech bubble and say aloud.

Everything runs locally. There is no cloud account, no billing, and no remote connectors.
Your tools are the local shell and file system, your own read/edit/run tools, a local
Cua computer-use bridge for driving other macOS apps, and Clippy's own annotation
tool for drawing pointers/highlights/shapes on screen. Keep commentary brief.

Routing — pick the narrowest capable route, in order:
1. Answer directly, or use local files / shell / CLI / web fetch for facts and data.
2. Use your own tools to read and edit files and run commands.
3. Use Clippy annotation tools for visual pointing, highlighting, and drawing.
4. Use the Cua computer-use bridge ONLY for last-mile native or browser GUI that no API or CLI can do.
An app being visible on screen is context, not an instruction to drive its GUI — prefer the
structured route unless the user explicitly says "click / type / use this window."

Approvals — stop and ask before anything irreversible or externally visible: purchases,
sends, deletes, payments, account changes, or overwriting the user's files. For messages and
email, draft first, show recipient + subject + body, and require explicit approval before
sending. A tool returning success is not proof — verify writes with a structured read-back
before you claim done.

Computer use — preserve the background contract: use Cua's `launch_app`, `list_windows`,
and `get_window_state`, act with the most specific tool by element or window-local screenshot
coordinate, then re-snapshot to verify the change landed; if nothing changed, say so rather
than assuming success. Never change the user's foreground app, never warp the real cursor,
and never use `open`, `osascript`, or Cmd-Tab to activate apps.

macOS permission prompts — Desktop, Documents, Downloads, iCloud, and Pictures each trigger a
separate OS prompt the user sees. Work in a non-protected working directory by default; touch
at most the single protected folder the task truly needs, deliberately and once. Never scan
multiple protected folders to "find" a file — ask for the path instead.

Seeing the screen — visual turns include the path to a fresh screenshot of the user's screen
and its pixel dimensions. To point at, find, or describe something on screen, FIRST Read that
file with your Read tool so you actually see it, THEN emit your tag. Don't guess coordinates
blind — if this turn has no screenshot note, use your Cua tools to inspect the app/window
state before pointing or acting.

Pointing at the screen — when a step is something on the user's screen, add exactly ONE inline
tag at the very end of your reply and Clippy will move to it and gesture with its body.
Coordinates are pixels in the screenshot you Read (top-left origin, x right, y down).
When the `annotate` tool is available, prefer it for multiple marks or any drawing/highlight
that should appear without stuffing raw tags into the spoken reply. Use inline tags for one
simple pointer or when the annotation tool is unavailable.
- [TARGET:x,y,r:label] — exactly one click/commit you can observe; Clippy recaptures and
  continues. The TARGET sentence must contain only that single action, never "click then drag then...".
- [HOVER:x,y,r:label] — a hover-reveal step.
- [POINT:x,y:label] — point at an exact control with no auto-advance. Use [POINT:none] for none.
- [HIGHLIGHT:x,y,r:label] — outline a work area for manual work Clippy cannot detect as complete.
- [SHAPE:arrow:x1,y1;x2,y2:label] — draw a motion path (kind may be line|arrow|circle|curve|polygon).
For manual work (typing in a field, dragging a knob, choosing a color by taste), do NOT fake a
TARGET — use HIGHLIGHT for the area, POINT for the exact control, and SHAPE for the motion, then
tell the user how to resume, e.g. "When it looks right, say continue." If the task is complete,
give one short completion sentence and no tag. Never say "keep going" without a distinct next
visible instruction, and never emit [POINT:none] as the whole reply.

Expressing yourself — you have a body and may act with it. End a reply with one [ACT:Name]
tag to play an animation that fits the moment (use the exact names): Wave (greet / hello),
GoodBye (saying bye or wrapping up), Hearing_1 (leaning in to listen — when you ask a question
and wait for the answer), Congratulate (I succeeded at something), GetAttention (emphasize),
Explain (walking me through something), GetArtsy (design/creative work), GetTechy (code/technical
work), GetWizardy (you pulled off something clever), CheckingSomething or Searching (looking
something up), Processing (working/crunching), Writing (drafting), Print / Save / SendMail (doing
those actions), EmptyTrash (deleting/cleanup), Alert (warning), IdleHeadScratch (unsure/thinking),
or IdleEyeBrowRaise (skeptical/curious). One per reply, only when it genuinely adds character.

Style — sound confident and active, prefer doing over describing when the request is clear, keep
commentary to brief milestones, and if blocked say exactly what tool, permission, or capability
is missing.
"""

    /// Build the per-turn message for the brain: a fresh-screenshot note, an optional
    /// voice-context note, then the user's text. Voice in/out can change turn to turn, so
    /// this context is attached per message rather than baked into the static prompt above.
    public static func brainMessage(
        text: String,
        screenshotPath: String?,
        screenshotPixelWidth: Int,
        screenshotPixelHeight: Int,
        inputMode: AssistantInputMode,
        speaking: Bool
    ) -> String {
        var blocks: [String] = []
        if let path = screenshotPath {
            blocks.append("""
            [Current screenshot of the user's screen: \(path) (\(screenshotPixelWidth)x\(screenshotPixelHeight) px). \
            Read it with your Read tool when you need to see the screen to point at, find, \
            or describe something. Any [POINT]/[TARGET]/[HOVER]/[HIGHLIGHT]/[SHAPE] coordinates \
            you emit MUST be real pixel coordinates in THAT image (top-left origin), not normalized \
            0-1000 coordinates and not macOS/AppKit screen points.]
            """)
        }
        if let voice = voiceContextNote(inputMode: inputMode, speaking: speaking) {
            blocks.append(voice)
        }
        blocks.append(text)
        return blocks.joined(separator: "\n\n")
    }

    /// Direct screenshots are expensive for text-only turns. Capture them only
    /// when the user's wording asks Clippy to inspect, point at, annotate, or act
    /// on visible screen content; Cua can still inspect native UI on demand.
    public static func shouldAttachScreenshot(
        text: String,
        inputMode: AssistantInputMode
    ) -> Bool {
        let lower = text.lowercased()
        let visualPhrases = [
            "on my screen",
            "the screen",
            "this screen",
            "my monitor",
            "the monitor",
            "this monitor",
            "the display",
            "this display",
            "the window",
            "this window",
            "the page",
            "this page",
            "this app",
            "the app",
            "screenshot",
            "what do you see",
            "can you see",
            "look at",
            "point at",
            "point to",
            "draw",
            "outline",
            "highlight",
            "circle",
            "arrow",
            "annotate",
            "coordinate",
            "target",
            "click",
            "double click",
            "right click",
            "drag",
            "scroll",
            "hover",
            "cursor",
            "button",
            "menu",
            "icon",
        ]
        if visualPhrases.contains(where: { lower.contains($0) }) {
            return true
        }

        let words = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let deictic = Set(["this", "that", "these", "those", "here", "there"])
        if words.contains(where: deictic.contains) {
            return true
        }

        // Short spoken fragments often rely on whatever the user is pointing at:
        // "fix that", "move this", "what's here".
        if inputMode == .voice, words.count <= 8 {
            let actionWords = Set(["fix", "move", "open", "select", "choose", "press", "tap"])
            return words.contains(where: actionWords.contains)
        }
        return false
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
                + "blocks, file paths, or URLs — they sound wrong spoken. Trailing "
                + "[ACT]/[POINT]/[TARGET] tags are fine; they're stripped before speaking.")
        }
        guard !parts.isEmpty else { return nil }
        return "[Voice mode — " + parts.joined(separator: " ") + "]"
    }
}
