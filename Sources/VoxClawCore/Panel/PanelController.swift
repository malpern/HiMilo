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
                }
            )
            .frame(width: panelWidth, height: panelHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        )
        panel.contentView = hostingView
        panel.onEsc = { [weak self] in self?.onStop() }
        panel.onSpace = { [weak self] in self?.onTogglePause() }
        panel.onSpeedUp = { [weak self] in self?.adjustSpeed(by: 0.1) }
        panel.onSpeedDown = { [weak self] in self?.adjustSpeed(by: -0.1) }

        // Start scaled down and transparent for materialize animation
        let scaleFactor: CGFloat = 0.92
        let scaledWidth = panelWidth * scaleFactor
        let scaledHeight = panelHeight * scaleFactor
        let startX = panelX + (panelWidth - scaledWidth) / 2
        let startY = panelY + (panelHeight - scaledHeight) / 2 + 12
        panel.setFrame(NSRect(x: startX, y: startY, width: scaledWidth, height: scaledHeight), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // Scale up + fade in (materialize)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)
            panel.animator().alphaValue = 1
        }

        Log.panel.info("show: panel ordered front at (\(Int(panelX), privacy: .public), \(Int(panelY), privacy: .public)), windowNumber=\(panel.windowNumber, privacy: .public)")
        self.panel = panel
        panel.makeKey()
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

        if settings.rememberOverlayPosition {
            settings.savedOverlayOrigin = panel.frame.origin
        }

        let frame = panel.frame
        let scaleFactor: CGFloat = 0.92
        let targetWidth = frame.width * scaleFactor
        let targetHeight = frame.height * scaleFactor
        let targetX = frame.origin.x + (frame.width - targetWidth) / 2
        let targetY = frame.origin.y + (frame.height - targetHeight) / 2 + 12

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight), display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                Log.panel.info("dismiss: animation complete, closing panel")
                self?.panel?.close()
                self?.panel = nil
            }
        })
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
