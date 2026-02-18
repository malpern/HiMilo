import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    let appState: AppState
    var onTogglePause: () -> Void = {}
    var onStop: () -> Void = {}
    var onStartListening: () -> Void = {}
    var onStopListening: () -> Void = {}
    var onReadText: (String) async -> Void = { _ in }

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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

            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("Launch at login error: \(error)")
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

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
