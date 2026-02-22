#if os(macOS)
import AppKit

final class FloatingPanel: NSPanel {
    var onEsc: (() -> Void)?
    var onSpace: (() -> Void)?
    var onSpeedUp: (() -> Void)?
    var onSpeedDown: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        // Allow interaction with overlay controls (e.g. pause/play button).
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hasShadow = true
        // Allow key events (Space/ESC) to reach the panel via local monitor
        // even when another app is visually active.
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onEsc?()           // ESC
        case 49: onSpace?()         // Space
        case 24: onSpeedUp?()       // + (=/+)
        case 27: onSpeedDown?()     // - (-/_)
        default: super.keyDown(with: event)
        }
    }
}
#endif
