import AppKit
import SceneKit

final class PetWindow: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: SCNView {
    var onDown: ((Double, Double) -> Void)?
    var onUp: (() -> Void)?
    var onRightDown: ((NSEvent) -> Void)?
    var onScroll: ((Double) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func local(_ e: NSEvent) -> (Double, Double) {
        let p = convert(e.locationInWindow, from: nil)
        return (Double(p.x), Double(bounds.height - p.y))
    }

    override func mouseDown(with e: NSEvent) {
        let (x, y) = local(e)
        onDown?(x, y)
    }

    override func mouseDragged(with e: NSEvent) {}
    override func mouseUp(with e: NSEvent) { onUp?() }
    override func rightMouseDown(with e: NSEvent) { onRightDown?(e) }

    override func scrollWheel(with e: NSEvent) {
        let d = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 16
        onScroll?(-Double(d))
    }
}

final class ActionItem: NSMenuItem {
    private let handler: (ActionItem) -> Void

    init(_ title: String, state: NSControl.StateValue = .off, enabled: Bool = true, _ handler: @escaping (ActionItem) -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        self.state = state
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler(self) }
}
