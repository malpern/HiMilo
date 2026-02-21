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
    private var globalKeyMonitor: Any?

    init(appState: AppState, settings: SettingsManager, onTogglePause: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.appState = appState
        self.settings = settings
        self.onTogglePause = onTogglePause
        self.onStop = onStop
    }

    func show() {
        guard let screen = NSScreen.main else {
            Log.panel.error("show: No main screen available")
            return
        }

        let appearance = settings.overlayAppearance
        let screenFrame = screen.visibleFrame
        let panelWidth = screenFrame.width * appearance.panelWidthFraction
        let panelHeight = appearance.panelHeight
        let cornerRadius = appearance.cornerRadius
        let topPadding: CGFloat = 8

        let panelX = screenFrame.midX - panelWidth / 2
        let panelY = screenFrame.maxY - panelHeight - topPadding

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
                }
            )
            .frame(width: panelWidth, height: panelHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        )
        panel.contentView = hostingView

        // Start off-screen for slide-down animation
        let startY = panelY + panelHeight + 20
        panel.setFrameOrigin(NSPoint(x: panelX, y: startY))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // Slide down + fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(NSPoint(x: panelX, y: panelY))
            panel.animator().alphaValue = 1
        }

        Log.panel.info("show: panel ordered front at (\(Int(panelX), privacy: .public), \(Int(panelY), privacy: .public)), windowNumber=\(panel.windowNumber, privacy: .public)")
        self.panel = panel
        startKeyMonitoring()
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

        let frame = panel.frame
        let targetY = frame.origin.y + frame.height + 20

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                Log.panel.info("dismiss: animation complete, closing panel")
                self?.panel?.close()
                self?.panel = nil
            }
        })
    }

    // MARK: - ESC Key Monitoring

    private func startKeyMonitoring() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.onStop()
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.onStop()
            }
        }
    }

    private func stopKeyMonitoring() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
    }

    private func showQuickSettings() {
        if let existing = quickSettingsWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = OverlayQuickSettings(settings: settings)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.level = .floating
        window.isReleasedWhenClosed = false

        // Position near the panel
        if let panel {
            let panelFrame = panel.frame
            let x = panelFrame.maxX + 8
            let y = panelFrame.midY - 170
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
        quickSettingsWindow = window
    }
}
