import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private var panel: FloatingPanel?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelWidth = screenFrame.width / 3
        let panelHeight: CGFloat = 162
        let cornerRadius: CGFloat = 20
        let topPadding: CGFloat = 8

        let panelX = screenFrame.midX - panelWidth / 2
        let panelY = screenFrame.maxY - panelHeight - topPadding

        let contentRect = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
        let panel = FloatingPanel(contentRect: contentRect)

        let hostingView = NSHostingView(rootView:
            FloatingPanelView(appState: appState)
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

        self.panel = panel
    }

    func dismiss() {
        guard let panel else { return }

        let frame = panel.frame
        let targetY = frame.origin.y + frame.height + 20

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: targetY))
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.panel?.close()
                self?.panel = nil
            }
        })
    }
}
