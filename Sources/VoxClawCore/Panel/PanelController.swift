#if os(macOS)
import AppKit
import os
import SwiftUI

@MainActor
final class PanelController {
    private var panel: FloatingPanel?
    private let appState: AppState
    private let settings: SettingsManager
    private let onTogglePause: () -> Void
    private let onStop: () -> Void
    private var quickSettingsWindow: NSWindow?
    private var localKeyMonitor: Any?
    private var previouslyFrontmost: NSRunningApplication?

    init(appState: AppState, settings: SettingsManager, onTogglePause: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.appState = appState
        self.settings = settings
        self.onTogglePause = onTogglePause
        self.onStop = onStop
    }

    func show() {
        // Idempotent: if we already have a panel, just keep it front. Otherwise
        // a courtesy-pause→resume cycle (which fires didChangeState(.playing)
        // a second time) creates a duplicate panel and orphans the original.
        if let existing = panel {
            existing.orderFrontRegardless()
            Log.panel.info("show: panel already exists (windowNumber=\(existing.windowNumber, privacy: .public)), keeping front")
            return
        }

        guard let screen = NSScreen.main else {
            Log.panel.error("show: No main screen available")
            return
        }

        let silent = appState.silentMode

        // Capture the app that currently has focus so we can return it after the
        // panel dismisses. Skip in silent mode — we won't take focus, so there's
        // nothing to restore. (Silent mode runs while a transcription tool may
        // be active; touching focus at all could break dictation.)
        if !silent, let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            previouslyFrontmost = frontmost
            Log.panel.info("show: captured frontmost app \(frontmost.bundleIdentifier ?? "unknown", privacy: .public)")
        } else {
            previouslyFrontmost = nil
        }

        let appearance = settings.overlayAppearance
        let screenFrame = screen.visibleFrame
        let panelWidth = screenFrame.width * appearance.panelWidthFraction
        let panelHeight = appearance.panelHeight
        let cornerRadius = appearance.cornerRadius
        let topPadding: CGFloat = 8

        let defaultX = screenFrame.midX - panelWidth / 2
        let defaultY = screenFrame.maxY - panelHeight - topPadding

        let panelX: CGFloat
        let panelY: CGFloat
        if settings.rememberOverlayPosition, let saved = settings.savedOverlayOrigin {
            panelX = saved.x
            panelY = saved.y
        } else {
            panelX = defaultX
            panelY = defaultY
        }

        let wordCount = appState.words.count
        let font = appearance.fontFamily
        Log.panel.info("show: creating panel \(Int(panelWidth), privacy: .public)x\(Int(panelHeight), privacy: .public), words=\(wordCount, privacy: .public), font=\(font, privacy: .public)")

        let contentRect = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
        let panel = FloatingPanel(contentRect: contentRect)

        let hostingView = NSHostingView(rootView:
            FloatingPanelView(
                appState: appState,
                settings: settings,
                onTogglePause: onTogglePause,
                onOpenSettings: { [weak self] in
                    self?.showQuickSettings()
                },
                onStop: { [weak self] in self?.onStop() }
            )
            .frame(width: panelWidth, height: panelHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        )
        panel.contentView = hostingView
        panel.onEsc = { [weak self] in self?.onStop() }
        panel.onSpace = { [weak self] in self?.onTogglePause() }
        panel.onSpeedUp = { [weak self] in self?.adjustSpeed(by: 0.1) }
        panel.onSpeedDown = { [weak self] in self?.adjustSpeed(by: -0.1) }

        panel.setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        Log.panel.info("show: panel ordered front at (\(Int(panelX), privacy: .public), \(Int(panelY), privacy: .public)), windowNumber=\(panel.windowNumber, privacy: .public), silent=\(silent, privacy: .public)")
        self.panel = panel
        // Never call makeKey(): on a non-activating panel it nudges keyboard
        // focus enough to disrupt the user's typing in their active app. Mouse
        // clicks on the panel still work (FloatingPanel.mouseDown becomes key
        // on demand), and the visible stop (X) button is the always-on dismiss
        // affordance. ESC/Space/+/- only fire when the panel is the key window
        // — i.e., after the user clicks into it.
    }

    func dismiss() {
        stopKeyMonitoring()
        let hadPanel = panel != nil
        let winNum = panel?.windowNumber ?? -1
        Log.panel.info("dismiss: hadPanel=\(hadPanel, privacy: .public), windowNumber=\(winNum, privacy: .public)")
        quickSettingsWindow?.close()
        quickSettingsWindow = nil
        guard let panel else {
            Log.panel.info("dismiss: no panel to dismiss")
            return
        }

        if settings.rememberOverlayPosition {
            settings.savedOverlayOrigin = panel.frame.origin
        }

        let frame = panel.frame
        let scaleFactor: CGFloat = 0.75
        let targetWidth = frame.width * scaleFactor
        let targetHeight = frame.height * scaleFactor
        let targetX = frame.origin.x + (frame.width - targetWidth) / 2
        let targetY = frame.origin.y + (frame.height - targetHeight) / 2

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            panel.animator().setFrame(NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight), display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel, weak self] in
            // Capture panel strongly so we can always close it, even if the
            // PanelController has been released by the session/coordinator
            // moving on. Otherwise the panel becomes a ghost stuck on screen
            // because no one calls close() on it.
            Task { @MainActor in
                Log.panel.info("dismiss: animation complete, closing panel")
                panel.close()
                self?.panel = nil
                self?.restorePreviousFrontmostIfAppropriate()
            }
        })
    }

    /// Reactivates whatever app had focus before the panel appeared. Skips if the
    /// captured app has terminated, or if the user has already moved focus to a
    /// third app (i.e. the current frontmost is neither VoxClaw nor the captured one).
    private func restorePreviousFrontmostIfAppropriate() {
        defer { previouslyFrontmost = nil }
        guard let prev = previouslyFrontmost else { return }
        guard !prev.isTerminated else {
            Log.panel.info("dismiss: skipping restore — captured app terminated")
            return
        }
        let currentFrontmost = NSWorkspace.shared.frontmostApplication
        let currentBundleId = currentFrontmost?.bundleIdentifier
        let voxClawBundleId = Bundle.main.bundleIdentifier
        let prevBundleId = prev.bundleIdentifier
        // If the user has moved to a third app, don't yank them back.
        if currentBundleId != voxClawBundleId && currentBundleId != prevBundleId {
            Log.panel.info("dismiss: skipping restore — user is now in \(currentBundleId ?? "unknown", privacy: .public)")
            return
        }
        Log.panel.info("dismiss: restoring focus to \(prevBundleId ?? "unknown", privacy: .public)")
        prev.activate()
    }

    // MARK: - Key Monitoring

    private func startKeyMonitoring() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 53: self?.onStop(); return nil           // ESC
            case 49: self?.onTogglePause(); return nil    // Space
            case 24: self?.adjustSpeed(by: 0.1); return nil  // +
            case 27: self?.adjustSpeed(by: -0.1); return nil // -
            default: return event
            }
        }
    }

    private func stopKeyMonitoring() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    private func adjustSpeed(by delta: Float) {
        let newSpeed = min(3.0, max(0.5, settings.voiceSpeed + delta))
        settings.voiceSpeed = (newSpeed * 10).rounded() / 10
    }

    private func showQuickSettings() {
        if let existing = quickSettingsWindow {
            existing.close()
            quickSettingsWindow = nil
            return
        }

        let settingsView = OverlayQuickSettings(settings: settings)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.contentView = NSHostingView(rootView:
            settingsView
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )

        // Position near the panel
        if let panel {
            let panelFrame = panel.frame
            let x = panelFrame.maxX + 8
            let y = panelFrame.midY - 100
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }

        window.orderFrontRegardless()
        quickSettingsWindow = window
    }
}
#endif
