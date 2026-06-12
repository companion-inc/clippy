import AppKit
import ClippyCore

@main
final class ClippyApp: NSObject, NSApplicationDelegate {
    private var mascotWindow: MascotWindowController?
    private var bubbleWindow: BubbleWindowController?
    private var renderer: CoreAnimationMorphRenderer?
    private var rasterRenderer: SpriteKitRasterCharacterRenderer?

    static func main() {
        let app = NSApplication.shared
        let delegate = ClippyApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = CGSize(width: 160, height: 140)
        let rasterRenderer = SpriteKitRasterCharacterRenderer(size: size)
        let mascotWindow = MascotWindowController(rendererView: rasterRenderer.view, size: size) { point in
            CGRect(origin: .zero, size: size).contains(point)
        }
        let bubbleWindow = BubbleWindowController()

        self.rasterRenderer = rasterRenderer
        self.mascotWindow = mascotWindow
        self.bubbleWindow = bubbleWindow

        mascotWindow.show()
        bubbleWindow.show(text: "ready", anchoredTo: mascotWindow.frame)
        showClippitRestPose(in: rasterRenderer)
    }

    private func showClippitRestPose(in rasterRenderer: SpriteKitRasterCharacterRenderer) {
        do {
            let root = Self.clippitResourceRoot()
            let spriteSheet = try ClippitSpriteSheet(packRoot: root)
            try rasterRenderer.show(animationName: "RestPose", spriteSheet: spriteSheet)
        } catch {
            let fallback = CoreAnimationMorphRenderer()
            renderer = fallback
            rasterRenderer.view.layer?.addSublayer(fallback.rootLayer)
            fallback.transition(to: MorphTargetPreset.neutral.path(in: fallback.bounds))
        }
    }

    private static func clippitResourceRoot() -> URL {
        let fileRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/Characters/Clippit")
        let cwdRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Resources/Characters/Clippit")
        let bundleRoot = Bundle.main.resourceURL?.appending(path: "Characters/Clippit")
        let candidates = [bundleRoot, cwdRoot, fileRoot].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appending(path: "character.json").path) } ?? fileRoot
    }
}
