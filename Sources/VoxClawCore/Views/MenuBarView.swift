import AppKit
import os
import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    let settings: SettingsManager
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void = {}
    var onReadText: (String) async -> Void = { _ in }

    @Environment(\.openWindow) private var openWindow
    @State private var clipboardPreview: String?

    var body: some View {
        Group {
            if appState.isActive {
                Button(appState.isPaused ? "Resume" : "Pause") {
                    onTogglePause()
                }
                .keyboardShortcut(" ", modifiers: [])

                Button("Stop") {
                    onStop()
                }
                .keyboardShortcut(.escape, modifiers: [])

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

            Divider()

            if settings.voiceEngine == .apple {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                } label: {
                    Label("Better Voice...", systemImage: "sparkles")
                }
            }

            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)

            Menu("VoxClaw Companion CLI") {
                Text("For terminal workflows, piping,")
                Text("and network listener mode.")
                Divider()
                Link("Learn More...", destination: URL(string: "https://github.com/malpern/VoxClaw")!)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            refreshClipboardPreview()
        }
    }

    private func refreshClipboardPreview() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clipboardPreview = nil
            return
        }
        let firstLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        let truncated = firstLine.count > 60 ? String(firstLine.prefix(60)) + "..." : firstLine
        clipboardPreview = "\"\(truncated)\""
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
