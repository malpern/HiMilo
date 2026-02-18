import AppKit

@MainActor
final class KeyboardMonitor {
    private var monitor: Any?
    private weak var session: ReadingSession?

    init(session: ReadingSession) {
        self.session = session
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 49: // Space
            session?.togglePause()
            return true
        case 53: // Escape
            session?.stop()
            return true
        case 123: // Left arrow
            session?.skip(seconds: -3)
            return true
        case 124: // Right arrow
            session?.skip(seconds: 3)
            return true
        default:
            return false
        }
    }
}
