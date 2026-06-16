import AppKit
import ClippyCore

@MainActor
final class ProviderKeysController: NSWindowController {
    private let deepgramField = NSSecureTextField()
    private let xaiField = NSSecureTextField()
    private let onSave: () -> Void

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 245),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clippy API Keys"
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
        loadExistingKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        loadExistingKeys()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeContentView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 245))

        let title = NSTextField(labelWithString: "Local provider keys")
        title.font = .boldSystemFont(ofSize: 18)
        title.frame = NSRect(x: 24, y: 196, width: 320, height: 24)
        container.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Deepgram listens. xAI speaks.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 24, y: 172, width: 320, height: 20)
        container.addSubview(subtitle)

        addRow(
            title: "Deepgram",
            placeholder: "DEEPGRAM_API_KEY",
            field: deepgramField,
            y: 124,
            in: container
        )
        addRow(
            title: "xAI",
            placeholder: "XAI_API_KEY",
            field: xaiField,
            y: 78,
            in: container
        )

        let save = NSButton(title: "Save", target: self, action: #selector(saveKeys))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 268, y: 24, width: 70, height: 30)
        container.addSubview(save)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(closeWindow))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: 346, y: 24, width: 70, height: 30)
        container.addSubview(cancel)

        return container
    }

    private func addRow(title: String, placeholder: String, field: NSSecureTextField, y: CGFloat, in container: NSView) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 24, y: y + 5, width: 90, height: 20)
        container.addSubview(label)

        field.placeholderString = placeholder
        field.frame = NSRect(x: 116, y: y, width: 300, height: 28)
        container.addSubview(field)
    }

    private func loadExistingKeys() {
        deepgramField.stringValue = ClippySecrets.deepgramAPIKey ?? ""
        xaiField.stringValue = ClippySecrets.xaiAPIKey ?? ""
    }

    @objc private func saveKeys() {
        do {
            try ClippySecrets.saveProviderKeys(
                deepgramAPIKey: deepgramField.stringValue,
                xaiAPIKey: xaiField.stringValue
            )
            onSave()
            close()
        } catch {
            presentError(error)
        }
    }

    @objc private func closeWindow() {
        close()
    }
}
