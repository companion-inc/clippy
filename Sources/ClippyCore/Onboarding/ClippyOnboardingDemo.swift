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
    public static let guidedIntroText = "Let's try something real. I'll open a tiny form, fill in your name, and draw on the screen so you can see what I did."
    public static let guidedWorkingText = "Opening the form"
    public static let visibleTaskLine = "Fill out this form with my name, then draw on it."
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
        try writePage(at: url)
        return url
    }

    public static func writePage(at url: URL) throws {
        try html().write(to: url, atomically: true, encoding: .utf8)
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
            .appendingPathComponent("OnboardingFormDemo", isDirectory: true)
    }

    public static func currentDisplayName() -> String {
        displayName(fullName: NSFullUserName(), accountName: NSUserName())
    }

    public static func displayName(fullName: String?, accountName: String? = nil) -> String {
        let candidates = [fullName, accountName]
        for candidate in candidates {
            let cleaned = cleanName(candidate)
            if cleaned.isEmpty == false {
                return cleaned
            }
        }
        return "Friend"
    }

    public static func taskPrompt(displayName: String, pageURL: URL) -> String {
        let name = Self.displayName(fullName: displayName)
        return """
        [Clippy onboarding demo task]
        The local browser should be showing this one-page demo form:
        \(pageURL.absoluteString)

        Do this as a real desktop task, using the same tools and screen context you use for normal user requests:
        1. Use the visible browser page.
        2. Fill the "Full name" field with "\(name)".
        3. Click "Save demo".
        4. Verify the page visibly shows the saved state.
        5. Then draw one simple Clippy-style screen annotation that calls out the filled name field.

        Do not describe the steps instead of doing them. Do not mention internal tool names. Keep the spoken reply to one short Clippy sentence.
        """
    }

    public static func html() -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Clippy Demo - Tiny Form</title>
          <style>
            :root {
              color-scheme: light;
              --ink: #171717;
              --muted: #5f6673;
              --line: #d4dbe7;
              --panel: #ffffff;
              --page: #eef2f7;
              --blue: #134fa8;
              --green: #087a4a;
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
              width: min(900px, calc(100vw - 40px));
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
              gap: 18px;
              padding: 24px 28px;
              border-bottom: 1px solid var(--line);
              background: #fbfcfe;
            }
            h1 {
              margin: 0;
              font-size: clamp(28px, 4vw, 42px);
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
              background: #fff1ef;
              color: var(--red);
              font-weight: 900;
              white-space: nowrap;
            }
            body.saved .status {
              background: #e8f8ef;
              color: var(--green);
            }
            .content {
              display: grid;
              grid-template-columns: minmax(0, 1fr) minmax(250px, 0.75fr);
              gap: 20px;
              padding: 24px;
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
            form {
              display: grid;
              gap: 14px;
              padding: 18px;
            }
            label {
              display: grid;
              gap: 7px;
              color: var(--muted);
              font-weight: 800;
            }
            input,
            textarea {
              width: 100%;
              border: 1px solid var(--line);
              border-radius: 8px;
              padding: 12px 13px;
              color: var(--ink);
              background: #fbfcfe;
              font: inherit;
              font-weight: 700;
            }
            input:focus,
            textarea:focus {
              outline: 4px solid rgba(255, 242, 154, 0.9);
              border-color: var(--ink);
              background: #fff;
            }
            textarea {
              min-height: 94px;
              resize: vertical;
            }
            .actions {
              display: flex;
              align-items: center;
              gap: 12px;
              margin-top: 2px;
            }
            button {
              height: 44px;
              border: 0;
              border-radius: 8px;
              padding: 0 18px;
              background: var(--blue);
              color: white;
              font: inherit;
              font-weight: 900;
            }
            button:disabled {
              background: #d4d9e2;
              color: #69707c;
            }
            .hint {
              color: var(--muted);
              font-size: 14px;
              font-weight: 700;
            }
            .panel {
              padding: 18px;
            }
            .panel h2 {
              padding: 0;
              margin: 0;
              font-size: 24px;
            }
            .panel p {
              margin: 10px 0 0;
              color: var(--muted);
              line-height: 1.45;
              font-size: 16px;
            }
            .sketch {
              margin-top: 18px;
              min-height: 150px;
              border: 2px dashed #b8c3d3;
              border-radius: 8px;
              display: grid;
              place-items: center;
              background: #fbfcfe;
              color: var(--muted);
              font-weight: 900;
              text-align: center;
              padding: 18px;
            }
            body.saved .sketch {
              border-color: var(--green);
              background: #f0fbf5;
              color: var(--green);
            }
            @media (max-width: 720px) {
              header {
                align-items: flex-start;
                flex-direction: column;
              }
              .content {
                grid-template-columns: 1fr;
              }
            }
          </style>
        </head>
        <body>
          <main aria-label="Clippy demo form">
            <header>
              <div>
                <h1>Let's try a form</h1>
                <p class="subhead">Clippy will fill one field, save it, then draw on this screen.</p>
              </div>
              <div id="status" class="status">Waiting for name</div>
            </header>
            <div class="content">
              <section aria-label="Demo form">
                <h2>Demo request</h2>
                <form id="demo-form">
                  <label for="full-name">
                    Full name
                    <input id="full-name" name="full-name" autocomplete="name" placeholder="Your name" autofocus>
                  </label>
                  <label for="request">
                    What should Clippy help with?
                    <textarea id="request" name="request">Help me finish a small desktop task.</textarea>
                  </label>
                  <div class="actions">
                    <button id="save-demo" type="submit" disabled>Save demo</button>
                    <span id="hint" class="hint">Enter a name to save.</span>
                  </div>
                </form>
              </section>
              <section class="panel" aria-label="Result">
                <h2 id="result-title">Ready when Clippy is</h2>
                <p id="result-copy">This page is local. Nothing is submitted anywhere.</p>
                <div id="sketch" class="sketch">Clippy's drawing goes on top of the screen, not inside this box.</div>
              </section>
            </div>
          </main>
          <script>
            const form = document.getElementById('demo-form');
            const nameInput = document.getElementById('full-name');
            const saveButton = document.getElementById('save-demo');
            const status = document.getElementById('status');
            const hint = document.getElementById('hint');
            const resultTitle = document.getElementById('result-title');
            const resultCopy = document.getElementById('result-copy');
            const sketch = document.getElementById('sketch');

            function sync() {
              const hasName = nameInput.value.trim().length > 0;
              saveButton.disabled = !hasName;
              status.textContent = hasName ? 'Ready to save' : 'Waiting for name';
              hint.textContent = hasName ? 'Now save the demo.' : 'Enter a name to save.';
            }

            nameInput.addEventListener('input', sync);
            form.addEventListener('submit', event => {
              event.preventDefault();
              const name = nameInput.value.trim();
              if (!name) {
                sync();
                return;
              }
              document.body.classList.add('saved');
              status.textContent = 'Saved';
              hint.textContent = 'Saved locally.';
              resultTitle.textContent = 'Saved for ' + name;
              resultCopy.textContent = 'Clippy filled the form and saved the demo.';
              sketch.textContent = 'Now Clippy can draw attention to the completed field.';
            });
            sync();
          </script>
        </body>
        </html>
        """
    }

    private static func cleanName(_ value: String?) -> String {
        guard let value else { return "" }
        let cleaned = value
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return "" }
        return String(cleaned.prefix(80))
    }
}
