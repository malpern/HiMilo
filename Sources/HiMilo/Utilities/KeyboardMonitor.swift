import AppKit

@MainActor
final class KeyboardMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var session: ReadingSession?

    init(session: ReadingSession) {
        self.session = session
    }

    func start() {
        // Local monitor for when the app has focus (menu bar)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }

        // Global monitor for when other apps have focus (since panel doesn't take focus)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
    }

    @discardableResult
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
