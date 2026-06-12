import AppKit
import ClippyCore

@main
final class ClippyApp: NSObject, NSApplicationDelegate {
    private var mascotWindow: MascotWindowController?
    private var bubbleWindow: BubbleWindowController?
    private var renderer: CoreAnimationMorphRenderer?

    static func main() {
        let app = NSApplication.shared
        let delegate = ClippyApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let renderer = CoreAnimationMorphRenderer()
        let mascotWindow = MascotWindowController(rendererLayer: renderer.rootLayer) { point in
            renderer.containsVisiblePoint(point)
        }
        let bubbleWindow = BubbleWindowController()

        self.renderer = renderer
        self.mascotWindow = mascotWindow
        self.bubbleWindow = bubbleWindow

        mascotWindow.show()
        bubbleWindow.show(text: "ready", anchoredTo: mascotWindow.frame)
        renderer.transition(to: MorphTargetPreset.neutral.path(in: renderer.bounds))
    }
}
