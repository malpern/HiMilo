import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    var onStartListening: () -> Void = {}
    var onStopListening: () -> Void = {}
    var onReadText: (String) async -> Void = { _ in }

    var body: some View {
        Group {
            if appState.isActive {
                Button(appState.isPaused ? "Resume" : "Pause") {
                    Task { await togglePause() }
                }
                .keyboardShortcut(" ", modifiers: [])

                Button("Stop") {
                    Task { await stop() }
                }
                .keyboardShortcut(.escape, modifiers: [])

                Divider()
            }

            Button("Paste & Read") {
                Task { await pasteAndRead() }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Read from File...") {
                Task { await readFromFile() }
            }

            Divider()

            Toggle(
                appState.isListening ? "HTTP Listener (port \(listenPort))" : "HTTP Listener",
                isOn: Binding(
                    get: { appState.isListening },
                    set: { newValue in
                        if newValue {
                            onStartListening()
                        } else {
                            onStopListening()
                        }
                    }
                )
            )

            if appState.isListening, let ip = NetworkListener.localIPAddress() {
                Text("\(ip):\(listenPort)")
                    .font(.caption)
            }

            Toggle("Audio Only Mode", isOn: Binding(
                get: { appState.audioOnly },
                set: { appState.audioOnly = $0 }
            ))

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var listenPort: UInt16 {
        CLIContext.shared?.port ?? 4140
    }

    private func togglePause() async {
        appState.isPaused.toggle()
        appState.sessionState = appState.isPaused ? .paused : .playing
    }

    private func stop() async {
        appState.reset()
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
            print("Error reading file: \(error)")
        }
    }
}
