import AppKit

/// A borderless, see-through panel that floats above other apps on every Space and never takes
/// focus, so clicking the pet leaves the selection in the app underneath alone.
final class OverlayPanel: NSPanel {
    init(size: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // The pet is drawn in sRGB. Matching the window to it lets the frames go to the screen
        // as they are; otherwise every frame is colour-converted on the CPU for the display.
        colorSpace = .sRGB
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Click-through until the controller sees the cursor over something solid.
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
