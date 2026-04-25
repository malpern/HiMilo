import SwiftUI

/// Shared peer list with speaker toggles. Used by both macOS SettingsView
/// and iOS iOSSettingsView. Shows discovered VoxClaw peers with on/off
/// switches and a toast on toggle.
public struct PeerSpeakerList: View {
    @Bindable var settings: SettingsManager
    var peerBrowser: PeerBrowser

    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    #if os(macOS)
    private static let localDeviceLabel = "This Mac"
    #else
    private static let localDeviceLabel = "This device"
    #endif

    public init(settings: SettingsManager, peerBrowser: PeerBrowser) {
        self.settings = settings
        self.peerBrowser = peerBrowser
    }

    public var body: some View {
        Section("VoxClaws On This Network") {
            if peerBrowser.peers.isEmpty {
                HStack(spacing: 8) {
                    if peerBrowser.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Searching...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(peerBrowser.peers) { peer in
                    peerRow(peer)
                }
            }

            if let toast = toastMessage {
                Label(toast, systemImage: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: toastMessage)
            }
        }
    }

    @MainActor
    private func peerRow(_ peer: DiscoveredPeer) -> some View {
        HStack {
            Text("\(peer.displayEmoji)  \(peer.name)")
            Spacer()
            if peer.baseURL != nil {
                let multipleDevices = peerBrowser.peers.filter({ $0.baseURL != nil }).count > 1
                if peer.isLocalMachine && !multipleDevices {
                    Text(Self.localDeviceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    speakerToggle(for: peer, isLocal: peer.isLocalMachine)
                }
                Button("Test") {
                    testPeer(peer)
                }
                .buttonStyle(.bordered)
                #if os(macOS)
                .controlSize(.small)
                #endif
            } else if peer.app == .voxclaw {
                Text("Resolving...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("OpenClaw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func speakerToggle(for peer: DiscoveredPeer, isLocal: Bool) -> some View {
        Toggle(isOn: Binding(
            get: {
                isLocal
                    ? !settings.relayPeerIDs.contains("__mute_local__")
                    : settings.relayPeerIDs.contains(peer.id)
            },
            set: { enabled in
                if isLocal {
                    if enabled {
                        settings.relayPeerIDs.remove("__mute_local__")
                        showToast("Speaking on \(peer.name)")
                    } else {
                        settings.relayPeerIDs.insert("__mute_local__")
                        showToast("Muted on \(peer.name)")
                    }
                } else {
                    if enabled {
                        settings.relayPeerIDs.insert(peer.id)
                        showToast("Also speaking on \(peer.name)")
                    } else {
                        settings.relayPeerIDs.remove(peer.id)
                        showToast("Stopped speaking on \(peer.name)")
                    }
                }
            }
        )) { EmptyView() }
        .toggleStyle(.switch)
        #if os(macOS)
        .controlSize(.small)
        #endif
    }

    private static let testQuotes = [
        "The ships hung in the sky in much the same way that bricks don't.",
        "Time is an illusion. Lunchtime doubly so.",
        "I love deadlines. I love the whooshing noise they make as they go by.",
        "Don't panic.",
        "So long, and thanks for all the fish.",
    ]

    private func testPeer(_ peer: DiscoveredPeer) {
        guard let baseURL = peer.baseURL,
              let url = URL(string: "\(baseURL)/read") else { return }
        let quote = Self.testQuotes.randomElement()!
        Task {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": quote, "relayed": true, "force_local": true])
            req.timeoutInterval = 3
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status >= 200 && status < 300 {
                    showToast("Sent test to \(peer.name)")
                } else {
                    showToast("Failed: HTTP \(status)")
                }
            } catch {
                showToast("Failed: \(error.localizedDescription)")
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation { toastMessage = nil }
        }
    }
}
