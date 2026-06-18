import Foundation

public enum ClippyOnboardingResumePoint: String, CaseIterable, Sendable {
    case welcome
    case brainChoice
    case brainHelp
    case chatGPT
    case claude
    case listening
    case voice
    case screenHelp
    case fileAccess
    case demo
    case controls

    public static let defaultsKey = "ClippyOnboardingResumePoint"

    public static func savedPoint(from rawValue: String?) -> Self {
        if rawValue == "demoComposer" {
            return .demo
        }
        if rawValue == "permission" || rawValue == "permissionWalkthrough" {
            return .screenHelp
        }
        guard let rawValue, let point = Self(rawValue: rawValue) else {
            return .welcome
        }
        return point
    }
}

public enum ClippyOnboardingDemo {
    public static let guidedIntroText = "Let me show you something real. I'll fill out a small form with your name, save it, and point to the field I changed."
    public static let guidedWorkingText = "Trying the form"
    public static let visibleTaskLine = ""
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
          <title>Clippy Demo - Form</title>
          <style>
            :root {
              color-scheme: light;
              --ink: #191b20;
              --muted: #626a78;
              --line: #d7dee9;
              --panel: #ffffff;
              --page: #f2f5f9;
              --blue: #1557b0;
              --green: #08724a;
              --red: #b42318;
              --yellow: #fff3a3;
              --soft: #f8fafc;
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
              width: min(820px, calc(100vw - 40px));
              background: var(--panel);
              border: 1px solid var(--line);
              border-radius: 8px;
              box-shadow: 0 18px 48px rgba(28, 39, 57, 0.16);
              overflow: hidden;
            }
            .topbar {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 12px;
              height: 46px;
              padding: 0 16px;
              border-bottom: 1px solid var(--line);
              background: var(--soft);
            }
            .dots {
              display: flex;
              gap: 7px;
            }
            .dot {
              width: 11px;
              height: 11px;
              border-radius: 50%;
              background: #c9d1de;
            }
            .dot:first-child { background: #ec6a5e; }
            .dot:nth-child(2) { background: #f5bf4f; }
            .dot:nth-child(3) { background: #61c554; }
            .title {
              font-size: 14px;
              font-weight: 900;
              color: #3d4654;
            }
            .body {
              display: grid;
              grid-template-columns: minmax(0, 1fr) 230px;
              gap: 24px;
              padding: 28px;
            }
            .intro {
              display: grid;
              gap: 4px;
              margin-bottom: 22px;
            }
            h1 {
              margin: 0;
              font-size: clamp(30px, 4vw, 40px);
              line-height: 1.08;
            }
            .subhead {
              margin: 0;
              color: var(--muted);
              font-size: 16px;
              line-height: 1.45;
            }
            .status {
              border-radius: 999px;
              padding: 8px 12px;
              background: #fff1ef;
              color: var(--red);
              font-weight: 900;
              white-space: nowrap;
              justify-self: start;
            }
            body.saved .status {
              background: #e8f8ef;
              color: var(--green);
            }
            form {
              display: grid;
              gap: 15px;
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
              padding: 13px 14px;
              color: var(--ink);
              background: var(--soft);
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
              flex-wrap: wrap;
              gap: 12px;
              margin-top: 4px;
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
            aside {
              display: grid;
              align-content: start;
              gap: 12px;
              padding: 18px;
              border: 1px solid var(--line);
              border-radius: 8px;
              background: var(--soft);
            }
            aside h2 {
              margin: 0;
              font-size: 18px;
            }
            aside p {
              margin: 0;
              color: var(--muted);
              line-height: 1.45;
              font-size: 15px;
            }
            .receipt {
              display: grid;
              gap: 6px;
              margin-top: 4px;
              padding-top: 12px;
              border-top: 1px solid var(--line);
              font-size: 14px;
              color: var(--muted);
            }
            .receipt strong {
              color: var(--ink);
            }
            @media (max-width: 720px) {
              .body {
                grid-template-columns: 1fr;
              }
            }
          </style>
        </head>
        <body>
          <main aria-label="Clippy demo form">
            <div class="topbar" aria-hidden="true">
              <div class="dots">
                <span class="dot"></span>
                <span class="dot"></span>
                <span class="dot"></span>
              </div>
              <div class="title">Clippy Demo</div>
              <div></div>
            </div>
            <div class="body">
              <section aria-label="Demo form">
                <div class="intro">
                  <h1>Quick request</h1>
                  <p class="subhead">Clippy will complete the missing name, save the form, and mark the changed field on screen.</p>
                  <div id="status" class="status">Needs name</div>
                </div>
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
              <aside aria-label="Result">
                <h2 id="result-title">Waiting for Clippy</h2>
                <p id="result-copy">This is a local demo page. Nothing is submitted anywhere.</p>
                <div class="receipt">
                  <span><strong>Status</strong></span>
                  <span id="receipt-copy">No changes saved yet.</span>
                </div>
              </aside>
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
            const receiptCopy = document.getElementById('receipt-copy');

            function sync() {
              const hasName = nameInput.value.trim().length > 0;
              saveButton.disabled = !hasName;
              status.textContent = hasName ? 'Ready to save' : 'Needs name';
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
              receiptCopy.textContent = 'Full name was completed and saved.';
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
