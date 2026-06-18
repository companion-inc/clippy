import CoreGraphics
import Foundation

public enum ClippyOnboardingDemo {
    public struct Target: Equatable, Sendable {
        public let center: CGPoint
        public let radius: CGFloat

        public init(center: CGPoint, radius: CGFloat) {
            self.center = center
            self.radius = radius
        }
    }

    public static let prefilledPrompt = "Make me a tiny welcome page, then point out one interesting thing on it."
    public static let controlsText = """
    Last thing: click me to open or close chat. Press Control+Space to type from anywhere. Hold Control+Option to talk. Hold Control to mark the screen, or tap Control twice for annotation mode. Right-click me for settings.
    """

    public static func createPage(
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil
    ) throws -> URL {
        let root = try pageRoot(fileManager: fileManager, supportDirectory: supportDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("index.html")
        try html().write(to: url, atomically: true, encoding: .utf8)
        return url
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
            x: windowFrame.midX,
            y: windowFrame.midY + max(28, min(86, windowFrame.height * 0.09))
        )
        return Target(
            center: CGPoint(
                x: min(max(center.x, windowFrame.minX + horizontalPadding), windowFrame.maxX - horizontalPadding),
                y: min(max(center.y, windowFrame.minY + 110), windowFrame.maxY - 90)
            ),
            radius: max(48, min(92, windowFrame.width * 0.07))
        )
    }

    public static func html() -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Clippy First Page</title>
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
              width: min(760px, calc(100vw - 40px));
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
              max-width: 12ch;
              font-size: clamp(46px, 8vw, 82px);
              line-height: 0.92;
            }
            p {
              margin: 22px 0 0;
              max-width: 56ch;
              font-size: clamp(17px, 2vw, 21px);
              line-height: 1.45;
            }
            .row {
              display: flex;
              flex-wrap: wrap;
              gap: 10px;
              margin-top: 28px;
            }
            .tag {
              border: 2px solid var(--ink);
              background: white;
              padding: 8px 11px;
              font-weight: 800;
              box-shadow: 4px 4px 0 rgba(17, 17, 17, 0.18);
            }
            .tag:nth-child(2) { color: var(--blue); }
            .tag:nth-child(3) { color: var(--rose); }
          </style>
        </head>
        <body>
          <main aria-label="Clippy onboarding page">
            <p class="eyebrow">First task</p>
            <h1>Hey, I'm Clippy.</h1>
            <p>I made this page from the onboarding bubble, opened it on your desktop, and can point at the part we are talking about.</p>
            <div class="row" aria-label="What Clippy just demonstrated">
              <span class="tag">type</span>
              <span class="tag">open</span>
              <span class="tag">point</span>
            </div>
          </main>
        </body>
        </html>
        """
    }
}
