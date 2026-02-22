#if os(macOS)
import AppKit
import os
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    let appState: AppState
    let settings: SettingsManager
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void = {}
    var onReadText: (String) async -> Void = { _ in }

    private var clipboardPreview: String? {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let firstLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        let truncated = firstLine.count > 60 ? String(firstLine.prefix(60)) + "..." : firstLine
        return "\"\(truncated)\""
    }

    var body: some View {
        Group {
            if appState.isActive {
                Button(appState.isPaused ? "Resume" : "Pause") {
                    onTogglePause()
                }
                .keyboardShortcut(" ", modifiers: [])
                .accessibilityIdentifier(AccessibilityID.MenuBar.pauseResume)

                Button("Stop") {
                    onStop()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier(AccessibilityID.MenuBar.stop)

                Divider()
            }

            if let preview = clipboardPreview {
                Button {
                    Task { await pasteAndRead() }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Read Clipboard")
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .accessibilityIdentifier(AccessibilityID.MenuBar.readClipboard)
            } else {
                Label {
                    Text("Read Clipboard")
                } icon: {
                    Image(systemName: "doc.on.clipboard")
                }
                .foregroundStyle(.tertiary)
            }

            Button {
                Task { await readFromFile() }
            } label: {
                Label("Read from File...", systemImage: "doc")
            }
            .accessibilityIdentifier(AccessibilityID.MenuBar.readFromFile)

            Divider()

            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityIdentifier(AccessibilityID.MenuBar.settings)

            if appState.isListening {
                Text("\u{1F5A5}\u{FE0F}  \(NetworkListener.localComputerName()):\(settings.networkListenerPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.autoClosedInstancesOnLaunch > 0 {
                let count = appState.autoClosedInstancesOnLaunch
                Text("Closed \(count) older instance\(count == 1 ? "" : "s") on launch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("About VoxClaw") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "about")
            }
            .accessibilityIdentifier(AccessibilityID.MenuBar.about)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityIdentifier(AccessibilityID.MenuBar.quit)
        }
    }

    @MainActor
    private func pasteAndRead() async {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }
        await onReadText(text)
    }

    @MainActor
    private func readFromFile() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            await onReadText(text)
        } catch {
            Log.app.error("Error reading file: \(error)")
        }
    }
}
#endif
