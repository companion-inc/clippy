import AppKit
import ClippyCore

@MainActor
final class ProviderKeysController: NSWindowController {
    private let sttField = NSSecureTextField()
    private let ttsField = NSSecureTextField()
    private let onSave: () -> Void

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 292),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Configure API Key"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.center()
        super.init(window: window)
        window.contentView = APIKeyPanel(sttField: sttField, ttsField: ttsField, save: { [weak self] in
            self?.saveKeys()
        }, cancel: { [weak self] in
            self?.close()
        })
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

    private func loadExistingKeys() {
        sttField.stringValue = ClippySecrets.deepgramAPIKey ?? ""
        ttsField.stringValue = ClippySecrets.xaiAPIKey ?? ""
    }

    private func saveKeys() {
        do {
            try ClippySecrets.saveVoiceAPIKeys(
                sttAPIKey: sttField.stringValue,
                ttsAPIKey: ttsField.stringValue
            )
            onSave()
            close()
        } catch {
            presentError(error)
        }
    }
}

private final class APIKeyPanel: NSView {
    private let sttField: NSSecureTextField
    private let ttsField: NSSecureTextField
    private let save: () -> Void
    private let cancel: () -> Void

    init(
        sttField: NSSecureTextField,
        ttsField: NSSecureTextField,
        save: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.sttField = sttField
        self.ttsField = ttsField
        self.save = save
        self.cancel = cancel
        super.init(frame: NSRect(x: 0, y: 0, width: 500, height: 292))
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        RetroPalette.face.setFill()
        bounds.fill()
        RetroBezel.draw(.window, in: bounds)
    }

    private func build() {
        addSubview(APIKeyTitleBar(title: "Clippy - Configure API Key"))

        let heading = label("Voice keys", x: 24, y: 48, width: 160, height: 22, size: 14, bold: true)
        addSubview(heading)

        let copy = label("STT listens through Deepgram. TTS speaks through xAI.", x: 24, y: 72, width: 420, height: 18)
        copy.textColor = RetroPalette.grayText
        addSubview(copy)

        addKeyRow(
            title: "STT API key",
            provider: "Deepgram",
            placeholder: "DEEPGRAM_API_KEY",
            field: sttField,
            y: 110
        )
        addKeyRow(
            title: "TTS API key",
            provider: "xAI",
            placeholder: "XAI_API_KEY",
            field: ttsField,
            y: 168
        )

        let saveButton = RetroButton(title: "Save")
        saveButton.isDefault = true
        saveButton.frame = NSRect(x: 315, y: 244, width: 75, height: 23)
        saveButton.onClick = save
        addSubview(saveButton)

        let cancelButton = RetroButton(title: "Cancel")
        cancelButton.frame = NSRect(x: 402, y: 244, width: 75, height: 23)
        cancelButton.onClick = cancel
        addSubview(cancelButton)
    }

    private func addKeyRow(
        title: String,
        provider: String,
        placeholder: String,
        field: NSSecureTextField,
        y: CGFloat
    ) {
        addSubview(label(title, x: 24, y: y, width: 100, height: 18, bold: true))
        let providerLabel = label(provider, x: 132, y: y, width: 160, height: 18)
        providerLabel.textColor = RetroPalette.grayText
        addSubview(providerLabel)

        let shell = RetroFieldShell(frame: NSRect(x: 24, y: y + 22, width: 452, height: 26))
        addSubview(shell)

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.font = RetroFont.ui(12)
        field.textColor = RetroPalette.text
        field.placeholderString = placeholder
        field.focusRingType = .none
        field.frame = NSRect(x: 5, y: 4, width: 442, height: 18)
        shell.addSubview(field)
    }

    private func label(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        size: CGFloat = 11,
        bold: Bool = false
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = RetroFont.ui(size, bold: bold)
        field.textColor = RetroPalette.text
        field.frame = NSRect(x: x, y: y, width: width, height: height)
        return field
    }
}

private final class APIKeyTitleBar: NSView {
    private let title: String

    init(title: String) {
        self.title = title
        super.init(frame: NSRect(x: 3, y: 3, width: 494, height: 22))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [RetroPalette.titleBar, RetroPalette.titleBarGradientEnd])?
            .draw(in: bounds, angle: 0)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: RetroFont.ui(12, bold: true),
            .foregroundColor: RetroPalette.captionText,
        ]
        (title as NSString).draw(in: NSRect(x: 8, y: 3, width: bounds.width - 16, height: 16), withAttributes: attrs)
    }
}

private final class RetroFieldShell: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        RetroPalette.fieldBackground.setFill()
        bounds.fill()
        RetroBezel.draw(.field, in: bounds)
    }
}
