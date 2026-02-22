import Foundation
import Network
import os

public enum PeerApp: String, Sendable {
    case voxclaw = "_voxclaw._tcp"
    case openclaw = "_openclaw._tcp"
}

/// Discovered peer on the local network.
public struct DiscoveredPeer: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let app: PeerApp

    public var displayEmoji: String {
        switch app {
        case .voxclaw:
            return "\u{1F50A}" // speaker
        case .openclaw:
            let lower = name.lowercased()
            if lower.contains("iphone") || lower.contains("ipad") || lower.contains("ipod") {
                return "\u{1F4F1}"
            }
            return "\u{1F5A5}\u{FE0F}"
        }
    }
}

/// Browses the local network for VoxClaw and OpenClaw instances via Bonjour.
@Observable
@MainActor
public final class PeerBrowser {
    public private(set) var peers: [DiscoveredPeer] = []
    public private(set) var isSearching = false

    private var voxclawBrowser: NWBrowser?
    private var openclawBrowser: NWBrowser?
    private var voxclawResults: Set<NWBrowser.Result> = []
    private var openclawResults: Set<NWBrowser.Result> = []

    public init() {}

    public func start() {
        guard voxclawBrowser == nil else { return }
        peers.removeAll()

        voxclawBrowser = startBrowser(type: "_voxclaw._tcp", app: .voxclaw)
        openclawBrowser = startBrowser(type: "_openclaw._tcp", app: .openclaw)
        isSearching = true
        Log.network.info("Peer browser started")
    }

    public func stop() {
        voxclawBrowser?.cancel()
        openclawBrowser?.cancel()
        voxclawBrowser = nil
        openclawBrowser = nil
        isSearching = false
        Log.network.info("Peer browser stopped")
    }

    private func startBrowser(type: String, app: PeerApp) -> NWBrowser {
        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isSearching = true
                    Log.network.info("Peer browser ready for \(type, privacy: .public)")
                case .failed(let error):
                    Log.network.error("Peer browser failed for \(type, privacy: .public): \(error)")
                case .cancelled:
                    break
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                switch app {
                case .voxclaw:
                    self?.voxclawResults = results
                case .openclaw:
                    self?.openclawResults = results
                }
                self?.rebuildPeers()
            }
        }

        browser.start(queue: .main)
        return browser
    }

    private func rebuildPeers() {
        var newPeers: [DiscoveredPeer] = []

        for result in voxclawResults {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            newPeers.append(DiscoveredPeer(id: "voxclaw.\(name)", name: name, app: .voxclaw))
        }

        for result in openclawResults {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            newPeers.append(DiscoveredPeer(id: "openclaw.\(name)", name: name, app: .openclaw))
        }

        peers = newPeers.sorted { $0.name < $1.name }
        Log.network.info("Peer browser found \(newPeers.count) peers")
    }
}
