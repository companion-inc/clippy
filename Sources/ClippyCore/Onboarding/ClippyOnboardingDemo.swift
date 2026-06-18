import CoreGraphics
import Foundation

public enum ClippyOnboardingResumePoint: String, CaseIterable, Sendable {
    case welcome
    case brainChoice
    case brainHelp
    case chatGPT
    case claude
    case listening
    case voice
    case permission
    case permissionWalkthrough
    case demo
    case controls

    public static let defaultsKey = "ClippyOnboardingResumePoint"

    public static func savedPoint(from rawValue: String?) -> Self {
        if rawValue == "demoComposer" {
            return .demo
        }
        guard let rawValue, let point = Self(rawValue: rawValue) else {
            return .welcome
        }
        return point
    }
}

public enum ClippyOnboardingDemo {
    public enum PageState: Sendable {
        case draft
        case completed
    }

    public struct Target: Equatable, Sendable {
        public let center: CGPoint
        public let radius: CGFloat

        public init(center: CGPoint, radius: CGFloat) {
            self.center = center
            self.radius = radius
        }
    }

    public static let guidedIntroText = "Watch this. I can clean up a messy note, mark what changed, and keep the mark attached to the page."
    public static let guidedWorkingText = "Opening the demo page"
    public static let taskIntroText = "Here's the messy note. Now I'll clean it up."
    public static let organizingText = "Cleaning up the note"
    public static let pointingIntroText = "I cleaned up the note. Now I'll mark the finished plan."
    public static let controlsText = """
    Last thing: click me to open or close chat. Press Control+Space to type from anywhere. Hold Control+Option to talk. Hold Control to mark the screen, or tap Control twice for annotation mode. Right-click me for settings.
    """

    public static func preparePage(
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil
    ) throws -> URL {
        let root = try pageRoot(fileManager: fileManager, supportDirectory: supportDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("index.html")
        try html(state: .draft).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func completePage(at url: URL) throws {
        try html(state: .completed).write(to: url, atomically: true, encoding: .utf8)
    }

    public static func pageRoot(
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil
    ) throws -> URL {
        let support: URL
        if let supportDirectory {
            support = supportDirectory
        } else if let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            support = directory
        } else {
            throw CocoaError(.fileNoSuchFile)
        }
        return support
            .appendingPathComponent("Clippy", isDirectory: true)
            .appendingPathComponent("OnboardingFirstTask", isDirectory: true)
    }

    public static func target(in windowFrame: CGRect) -> Target {
        let horizontalPadding = max(70, min(180, windowFrame.width * 0.18))
        let center = CGPoint(
            x: windowFrame.midX + max(70, min(190, windowFrame.width * 0.16)),
            y: windowFrame.midY + max(18, min(56, windowFrame.height * 0.06))
        )
        return Target(
            center: CGPoint(
                x: min(max(center.x, windowFrame.minX + horizontalPadding), windowFrame.maxX - horizontalPadding),
                y: min(max(center.y, windowFrame.minY + 110), windowFrame.maxY - 90)
            ),
            radius: max(48, min(92, windowFrame.width * 0.07))
        )
    }

    public static func html(state: PageState = .draft) -> String {
        let completed = state == .completed
        let resultClass = completed ? "result done" : "result"
        let resultEyebrow = completed ? "Clippy finished" : "Waiting for Clippy"
        let resultTitle = completed ? "A simple plan" : "Ready for cleanup"
        let resultBody = completed
            ? "I turned the rough note into three next steps."
            : "This area will change when Clippy does the task."
        let resultItems = completed
            ? """
              <li>Send the deck before lunch.</li>
              <li>Ask design for the hero screenshot.</li>
              <li>Add the download link to the README.</li>
            """
            : """
              <li class="muted">Waiting for the plan...</li>
              <li class="muted">Waiting for the plan...</li>
              <li class="muted">Waiting for the plan...</li>
            """
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Clippy First Task</title>
          <style>
            :root {
              color-scheme: light;
              --ink: #111111;
              --paper: #fff9c7;
              --blue: #174ea6;
              --green: #0b7a5b;
              --rose: #b3261e;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              background:
                linear-gradient(90deg, rgba(17, 17, 17, 0.06) 1px, transparent 1px),
                linear-gradient(rgba(17, 17, 17, 0.06) 1px, transparent 1px),
                #f5f7fb;
              background-size: 24px 24px;
              color: var(--ink);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }
            main {
              width: min(920px, calc(100vw - 40px));
              background: var(--paper);
              border: 3px solid var(--ink);
              box-shadow: 12px 12px 0 var(--blue);
              padding: clamp(26px, 5vw, 44px);
            }
            .eyebrow {
              margin: 0 0 12px;
              color: var(--green);
              font-size: 14px;
              font-weight: 800;
              letter-spacing: 0.08em;
              text-transform: uppercase;
            }
            h1 {
              margin: 0;
              max-width: 15ch;
              font-size: clamp(38px, 6vw, 68px);
              line-height: 0.96;
            }
            p {
              margin: 22px 0 0;
              max-width: 56ch;
              font-size: clamp(17px, 2vw, 21px);
              line-height: 1.45;
            }
            .workbench {
              display: grid;
              grid-template-columns: repeat(2, minmax(0, 1fr));
              gap: 16px;
              margin-top: 30px;
            }
            .note,
            .result {
              border: 2px solid var(--ink);
              background: white;
              padding: 18px;
              box-shadow: 4px 4px 0 rgba(17, 17, 17, 0.18);
            }
            .note h2,
            .result h2 {
              margin: 0;
              font-size: 24px;
            }
            .note pre {
              margin: 14px 0 0;
              white-space: pre-wrap;
              font: 700 17px/1.45 ui-monospace, "SFMono-Regular", Menlo, monospace;
            }
            .result {
              position: relative;
            }
            .result.done {
              border-color: var(--green);
              box-shadow: 4px 4px 0 rgba(11, 122, 91, 0.32);
            }
            .pill {
              display: inline-block;
              margin-bottom: 10px;
              border: 2px solid var(--ink);
              padding: 5px 8px;
              background: #f5f7fb;
              color: var(--blue);
              font-size: 13px;
              font-weight: 900;
              text-transform: uppercase;
            }
            .result.done .pill {
              background: #e5fff5;
              color: var(--green);
            }
            .result p {
              margin-top: 10px;
              font-size: 16px;
            }
            ol {
              margin: 14px 0 0;
              padding-left: 22px;
              font-weight: 800;
              line-height: 1.55;
            }
            .muted {
              color: #707070;
              font-weight: 700;
            }
            @media (max-width: 720px) {
              .workbench {
                grid-template-columns: 1fr;
              }
            }
          </style>
        </head>
        <body>
          <main aria-label="Clippy onboarding page">
            <p class="eyebrow">First task</p>
            <h1>Clean up a messy note.</h1>
            <p>I made this page from the onboarding bubble. Now I can turn a rough note into a short plan and show you what changed.</p>
            <section class="workbench" aria-label="Clippy first task">
              <article class="note" aria-label="Messy note">
                <h2>Messy note</h2>
                <pre>send deck tmrw&#10;ask design hero shot&#10;readme needs download link</pre>
              </article>
              <article id="result" class="\(resultClass)" aria-label="Clippy result">
                <span class="pill">\(resultEyebrow)</span>
                <h2>\(resultTitle)</h2>
                <p>\(resultBody)</p>
                <ol>
                \(resultItems)
                </ol>
              </article>
            </section>
          </main>
        </body>
        </html>
        """
    }
}
