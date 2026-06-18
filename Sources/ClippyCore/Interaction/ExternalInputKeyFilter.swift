import AppKit

public enum ExternalInputKeyFilter {
    public nonisolated static func accepts(
        keyCode: UInt16,
        characters: String?,
        modifierFlags: NSEvent.ModifierFlags,
        inputAlreadyOpen: Bool
    ) -> Bool {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
        guard modifierFlags.intersection(blockedModifiers).isEmpty else { return false }

        switch keyCode {
        case 36, 51, 53, 76, 117:
            return inputAlreadyOpen
        default:
            guard let characters, characters.rangeOfCharacter(from: .newlines) == nil else {
                return false
            }
            if inputAlreadyOpen {
                return characters.isEmpty == false
            }
            return characters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }
}
