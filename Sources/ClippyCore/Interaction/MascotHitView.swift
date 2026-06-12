import AppKit

public final class MascotHitView: NSView {
    private let visibleHitTest: (NSPoint) -> Bool

    public init(frame: NSRect, visibleHitTest: @escaping (NSPoint) -> Bool) {
        self.visibleHitTest = visibleHitTest
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public override var isFlipped: Bool {
        false
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        visibleHitTest(point) ? self : nil
    }
}
