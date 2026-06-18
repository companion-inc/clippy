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
    public enum PageState: String, CaseIterable, Sendable {
        case profile
        case portfolioFixed
        case screening
        case screeningComplete
        case review
        case submitted
    }

    public enum FocusTarget: Sendable {
        case portfolioField
        case nextButton
        case screeningAnswer
        case submitButton
        case confirmation
    }

    public struct Target: Equatable, Sendable {
        public let center: CGPoint
        public let radius: CGFloat

        public init(center: CGPoint, radius: CGFloat) {
            self.center = center
            self.radius = radius
        }
    }

    public static let guidedIntroText = "Watch this. I can read a screen, complete the next steps, and show you where I acted."
    public static let guidedWorkingText = "Opening the demo page"
    public static let taskIntroText = "I'll finish this application flow: fix the missing link, answer the question, and submit the review."
    public static let portfolioFilledText = "Filled the missing portfolio link."
    public static let screeningAnsweredText = "Answered the required screening question."
    public static let organizingText = "Working through the form"
    public static let submitText = "Final check looks good. Submitting it now."
    public static let nextClickText = "Clicking Next."
    public static let submittedText = "Done. The application is submitted."
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
        try writePage(at: url, state: .profile)
        return url
    }

    public static func writePage(at url: URL, state: PageState) throws {
        try html(state: state).write(to: url, atomically: true, encoding: .utf8)
    }

    public static func completePage(at url: URL) throws {
        try writePage(at: url, state: .submitted)
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

    public static func target(_ focus: FocusTarget, in windowFrame: CGRect) -> Target {
        let relative: CGPoint
        let radius: CGFloat
        switch focus {
        case .portfolioField:
            relative = CGPoint(x: 0.34, y: 0.51)
            radius = 58
        case .nextButton:
            relative = CGPoint(x: 0.47, y: 0.22)
            radius = 54
        case .screeningAnswer:
            relative = CGPoint(x: 0.37, y: 0.48)
            radius = 72
        case .submitButton:
            relative = CGPoint(x: 0.47, y: 0.23)
            radius = 58
        case .confirmation:
            relative = CGPoint(x: 0.50, y: 0.53)
            radius = 82
        }
        let center = CGPoint(
            x: windowFrame.minX + windowFrame.width * relative.x,
            y: windowFrame.minY + windowFrame.height * relative.y
        )
        return Target(
            center: CGPoint(
                x: min(max(center.x, windowFrame.minX + 80), windowFrame.maxX - 80),
                y: min(max(center.y, windowFrame.minY + 110), windowFrame.maxY - 100)
            ),
            radius: max(44, min(radius, windowFrame.width * 0.08))
        )
    }

    public static func target(in windowFrame: CGRect) -> Target {
        target(.portfolioField, in: windowFrame)
    }

    public static func isDemoContext(_ context: DesktopContextSnapshot, pageURL: URL) -> Bool {
        let demoTitle = "Clippy Demo"
        if context.browser?.title?.localizedCaseInsensitiveContains(demoTitle) == true
            || context.window?.title?.localizedCaseInsensitiveContains(demoTitle) == true {
            return true
        }
        guard let browserURL = context.browser?.url,
              let url = URL(string: browserURL) else {
            return false
        }
        return url.standardizedFileURL.path == pageURL.standardizedFileURL.path
    }

    public static func html(state: PageState = .profile) -> String {
        let vm = PageViewModel(state: state)
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Clippy Demo - Application Review</title>
          <style>
            :root {
              color-scheme: light;
              --ink: #151515;
              --muted: #666c76;
              --line: #d8dde6;
              --panel: #ffffff;
              --page: #eef2f6;
              --blue: #174ea6;
              --green: #0a7b4f;
              --red: #b42318;
              --yellow: #fff29a;
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              background: var(--page);
              color: var(--ink);
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            }
            main {
              width: min(980px, calc(100vw - 40px));
              background: var(--panel);
              border: 1px solid var(--line);
              border-radius: 8px;
              box-shadow: 0 18px 60px rgba(18, 28, 45, 0.16);
              overflow: hidden;
            }
            header {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 16px;
              padding: 22px 26px;
              border-bottom: 1px solid var(--line);
              background: #fbfcfe;
            }
            h1 {
              margin: 0;
              font-size: clamp(26px, 4vw, 38px);
              line-height: 1.05;
            }
            .subhead {
              margin: 8px 0 0;
              color: var(--muted);
              font-size: 16px;
            }
            .status {
              border-radius: 999px;
              padding: 8px 12px;
              font-weight: 800;
              white-space: nowrap;
            }
            .status.blocked {
              background: #fff1ef;
              color: var(--red);
            }
            .status.ready,
            .status.good {
              background: #e8f8ef;
              color: var(--green);
            }
            .progress {
              display: grid;
              grid-template-columns: repeat(3, 1fr);
              gap: 8px;
              padding: 18px 24px 0;
            }
            .progress span {
              height: 8px;
              border-radius: 999px;
              background: #dce2eb;
            }
            .progress .active,
            .progress .done {
              background: var(--blue);
            }
            .content {
              display: grid;
              grid-template-columns: minmax(0, 1.15fr) minmax(260px, 0.85fr);
              gap: 20px;
              padding: 20px 24px 24px;
            }
            section {
              border: 1px solid var(--line);
              border-radius: 8px;
              background: #fff;
            }
            section h2 {
              margin: 0;
              padding: 18px 18px 0;
              font-size: 20px;
            }
            .fields {
              display: grid;
              gap: 10px;
              padding: 16px 18px 18px;
            }
            .field {
              display: grid;
              grid-template-columns: 150px 1fr auto;
              align-items: center;
              gap: 12px;
              min-height: 48px;
              border: 1px solid var(--line);
              border-radius: 8px;
              padding: 12px;
              background: #fbfcfe;
            }
            .label {
              color: var(--muted);
              font-weight: 700;
            }
            .value {
              font-weight: 800;
            }
            .ok .badge {
              color: var(--green);
            }
            .missing {
              border-color: #f0b8b2;
              background: #fff8f7;
            }
            .missing .badge {
              color: var(--red);
            }
            .focus {
              border-color: var(--ink);
              background: var(--yellow);
              box-shadow: 0 0 0 4px rgba(255, 242, 154, 0.8);
            }
            .answer {
              min-height: 146px;
              align-items: start;
            }
            .answer .value {
              line-height: 1.45;
            }
            .button-row {
              display: flex;
              gap: 10px;
              padding: 0 18px 18px;
            }
            .button {
              flex: 1;
              height: 44px;
              border: 0;
              border-radius: 8px;
              background: #d4d9e2;
              color: #69707c;
              font-weight: 900;
            }
            .button.primary {
              background: var(--blue);
              color: white;
            }
            .pulse {
              box-shadow: 0 0 0 4px rgba(23, 78, 166, 0.18);
            }
            .insight {
              padding: 18px;
            }
            .pill {
              display: inline-flex;
              align-items: center;
              border-radius: 999px;
              padding: 6px 10px;
              background: #eef4ff;
              color: var(--blue);
              font-weight: 900;
              font-size: 13px;
            }
            .insight.done .pill {
              background: #e8f8ef;
              color: var(--green);
            }
            .insight h2 {
              padding: 0;
              margin-top: 18px;
              font-size: 28px;
            }
            .insight p {
              margin: 10px 0 0;
              color: var(--muted);
              font-size: 16px;
              line-height: 1.45;
            }
            ol {
              margin: 18px 0 0;
              padding-left: 22px;
              font-weight: 800;
              line-height: 1.65;
            }
            .muted {
              color: var(--muted);
              font-weight: 700;
            }
            .receipt {
              display: grid;
              place-items: center;
              min-height: 310px;
              text-align: center;
              padding: 34px;
            }
            .check {
              width: 76px;
              height: 76px;
              display: grid;
              place-items: center;
              margin: 0 auto 18px;
              border-radius: 50%;
              background: #e8f8ef;
              color: var(--green);
              font-size: 42px;
              font-weight: 900;
            }
            @media (max-width: 720px) {
              header {
                align-items: flex-start;
                flex-direction: column;
              }
              .content {
                grid-template-columns: 1fr;
              }
              .field {
                grid-template-columns: 1fr;
              }
            }
          </style>
        </head>
        <body>
          <main aria-label="Clippy demo page">
            <header>
              <div>
                <h1>Application Review</h1>
                <p class="subhead">A realistic flow with three steps for Clippy to finish.</p>
              </div>
              <div class="\(vm.statusClass)">\(vm.statusText)</div>
            </header>
            <div class="progress" aria-label="Progress">
              \(vm.progressHTML)
            </div>
            <div class="content">
              <section aria-label="Application task">
                <h2>\(vm.formTitle)</h2>
                \(vm.formHTML)
              </section>
              <section id="result" class="\(vm.insightClass)" aria-label="Clippy result">
                <span class="pill">\(vm.insightEyebrow)</span>
                <h2>\(vm.insightTitle)</h2>
                <p>\(vm.insightBody)</p>
                <ol>
                \(vm.insightItems)
                </ol>
              </section>
            </div>
          </main>
        </body>
        </html>
        """
    }
}

private struct PageViewModel {
    let state: ClippyOnboardingDemo.PageState

    var step: Int {
        switch state {
        case .profile, .portfolioFixed:
            return 1
        case .screening, .screeningComplete:
            return 2
        case .review, .submitted:
            return 3
        }
    }

    var statusText: String {
        switch state {
        case .profile:
            return "Step 1 blocked"
        case .portfolioFixed:
            return "Step 1 ready"
        case .screening:
            return "Step 2 blocked"
        case .screeningComplete:
            return "Step 2 ready"
        case .review:
            return "Ready to submit"
        case .submitted:
            return "Submitted"
        }
    }

    var statusClass: String {
        switch state {
        case .profile, .screening:
            return "status blocked"
        case .portfolioFixed, .screeningComplete, .review:
            return "status ready"
        case .submitted:
            return "status good"
        }
    }

    var progressHTML: String {
        (1...3).map { index in
            let klass = index < step || state == .submitted ? "done" : (index == step ? "active" : "")
            return "<span class=\"\(klass)\"></span>"
        }.joined(separator: "\n")
    }

    var formTitle: String {
        switch state {
        case .profile, .portfolioFixed:
            return "Step 1: Profile"
        case .screening, .screeningComplete:
            return "Step 2: Screening"
        case .review:
            return "Step 3: Review"
        case .submitted:
            return "Application sent"
        }
    }

    var formHTML: String {
        switch state {
        case .profile:
            return profileHTML(portfolioValue: "Missing required URL", portfolioClass: "field missing focus", badge: "Fix", nextClass: "button", nextLabel: "Next")
        case .portfolioFixed:
            return profileHTML(portfolioValue: "example.com/portfolio", portfolioClass: "field ok focus", badge: "Ready", nextClass: "button primary pulse", nextLabel: "Next")
        case .screening:
            return screeningHTML(answer: "Missing answer", answerClass: "field missing answer focus", badge: "Fix", nextClass: "button", nextLabel: "Next")
        case .screeningComplete:
            return screeningHTML(
                answer: "I care about fast, useful tools that remove busywork from creative teams.",
                answerClass: "field ok answer focus",
                badge: "Ready",
                nextClass: "button primary pulse",
                nextLabel: "Next"
            )
        case .review:
            return """
            <div class="fields">
              <div class="field ok">
                <div class="label">Profile</div>
                <div class="value">Portfolio link added</div>
                <div class="badge">Ready</div>
              </div>
              <div class="field ok">
                <div class="label">Screening</div>
                <div class="value">Short answer completed</div>
                <div class="badge">Ready</div>
              </div>
              <div class="field ok focus">
                <div class="label">Consent</div>
                <div class="value">Checked</div>
                <div class="badge">Ready</div>
              </div>
            </div>
            <div class="button-row">
              <button class="button primary pulse">Submit application</button>
            </div>
            """
        case .submitted:
            return """
            <div class="receipt">
              <div>
                <div class="check">&#10003;</div>
                <h2>Submitted</h2>
                <p class="subhead">Clippy finished the three-step flow.</p>
              </div>
            </div>
            """
        }
    }

    var insightClass: String {
        state == .submitted ? "insight done" : "insight"
    }

    var insightEyebrow: String {
        state == .submitted ? "Finished" : "Clippy is working"
    }

    var insightTitle: String {
        switch state {
        case .profile:
            return "Portfolio link is missing"
        case .portfolioFixed:
            return "Thing 1 done"
        case .screening:
            return "Question needs an answer"
        case .screeningComplete:
            return "Thing 2 done"
        case .review:
            return "Thing 3 is ready"
        case .submitted:
            return "All done"
        }
    }

    var insightBody: String {
        switch state {
        case .profile:
            return "The form looks close, but Next is blocked by one missing required field."
        case .portfolioFixed:
            return "I filled the missing portfolio URL. Now I can move to the next step."
        case .screening:
            return "The next screen needs a concise answer before it can continue."
        case .screeningComplete:
            return "I wrote the answer and the next button is ready."
        case .review:
            return "Everything is ready. I checked consent and can submit."
        case .submitted:
            return "I completed three actions on the demo screen."
        }
    }

    var insightItems: String {
        switch state {
        case .profile:
            return """
              <li class="muted">Find the required missing field.</li>
              <li class="muted">Fill it without bothering you.</li>
              <li class="muted">Click through the flow.</li>
            """
        case .portfolioFixed:
            return """
              <li>Filled portfolio link.</li>
              <li>Next button is available.</li>
              <li class="muted">Moving to screening.</li>
            """
        case .screening:
            return """
              <li>Read the prompt.</li>
              <li class="muted">Draft the short answer.</li>
              <li class="muted">Click Next when ready.</li>
            """
        case .screeningComplete:
            return """
              <li>Answered the screening question.</li>
              <li>Next button is available.</li>
              <li class="muted">Moving to review.</li>
            """
        case .review:
            return """
              <li>Portfolio link added.</li>
              <li>Screening answer added.</li>
              <li>Consent checked.</li>
            """
        case .submitted:
            return """
              <li>Filled the missing field.</li>
              <li>Answered the required question.</li>
              <li>Submitted the application.</li>
            """
        }
    }

    private func profileHTML(
        portfolioValue: String,
        portfolioClass: String,
        badge: String,
        nextClass: String,
        nextLabel: String
    ) -> String {
        """
        <div class="fields">
          <div class="field ok">
            <div class="label">Resume</div>
            <div class="value">Uploaded</div>
            <div class="badge">Ready</div>
          </div>
          <div class="field ok">
            <div class="label">Work authorization</div>
            <div class="value">Yes</div>
            <div class="badge">Ready</div>
          </div>
          <div class="\(portfolioClass)" id="portfolio-field">
            <div class="label">Portfolio link</div>
            <div class="value">\(portfolioValue)</div>
            <div class="badge">\(badge)</div>
          </div>
        </div>
        <div class="button-row">
          <button class="\(nextClass)">\(nextLabel)</button>
        </div>
        """
    }

    private func screeningHTML(
        answer: String,
        answerClass: String,
        badge: String,
        nextClass: String,
        nextLabel: String
    ) -> String {
        """
        <div class="fields">
          <div class="field ok">
            <div class="label">Question</div>
            <div class="value">Why are you interested in this role?</div>
            <div class="badge">Required</div>
          </div>
          <div class="\(answerClass)" id="screening-answer">
            <div class="label">Short answer</div>
            <div class="value">\(answer)</div>
            <div class="badge">\(badge)</div>
          </div>
        </div>
        <div class="button-row">
          <button class="\(nextClass)">\(nextLabel)</button>
        </div>
        """
    }
}
