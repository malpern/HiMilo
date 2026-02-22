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
    public let host: String?
    public let port: UInt16?

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

    /// Base URL for this peer's HTTP API.
    public var baseURL: String? {
        guard app == .voxclaw, let host, !host.isEmpty, let port else { return nil }
        return "http://\(normalizedHostForURL(host)):\(port)"
    }

    /// URL host formatting:
    /// - IPv4 / DNS names stay unchanged.
    /// - IPv6 literals must be enclosed in brackets per RFC 3986.
    private func normalizedHostForURL(_ host: String) -> String {
        let raw = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return raw }

        // Some Network.framework-resolved IPv4 hosts can include an interface scope suffix
        // (e.g. "192.168.1.228%en0"), which is invalid in URL host syntax for IPv4.
        let hostWithoutInvalidIPv4Scope: String
        if let percent = raw.firstIndex(of: "%"), !raw[..<percent].contains(":") {
            hostWithoutInvalidIPv4Scope = String(raw[..<percent])
        } else {
            hostWithoutInvalidIPv4Scope = raw
        }

        if hostWithoutInvalidIPv4Scope.hasPrefix("[") && hostWithoutInvalidIPv4Scope.hasSuffix("]") {
            return hostWithoutInvalidIPv4Scope
        }
        if hostWithoutInvalidIPv4Scope.contains(":") {
            return "[\(hostWithoutInvalidIPv4Scope)]"
        }
        return hostWithoutInvalidIPv4Scope
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
    /// Cache of resolved host:port keyed by service name.
    private var resolvedAddresses: [String: (host: String, port: UInt16)] = [:]

    public init() {}

    public func start() {
        guard voxclawBrowser == nil else { return }
        peers.removeAll()
        resolvedAddresses.removeAll()

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
                // Resolve VoxClaw endpoints and prefer resolved addresses over TXT metadata.
                if app == .voxclaw {
                    self?.resolvePeers()
                }
            }
        }

        browser.start(queue: .main)
        return browser
    }

    private func rebuildPeers() {
        var newPeers: [DiscoveredPeer] = []

        for result in voxclawResults {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            // Prefer live endpoint resolution over TXT metadata.
            var (host, port): (String?, UInt16?)
            if let cached = resolvedAddresses[name] {
                host = cached.host
                port = cached.port
            } else {
                (host, port) = extractTXTMetadata(from: result)
            }
            newPeers.append(DiscoveredPeer(id: "voxclaw.\(name)", name: name, app: .voxclaw, host: host, port: port))
        }

        for result in openclawResults {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            newPeers.append(DiscoveredPeer(id: "openclaw.\(name)", name: name, app: .openclaw, host: nil, port: nil))
        }

        peers = newPeers.sorted { $0.name < $1.name }
        Log.network.info("Peer browser found \(newPeers.count) peers")
    }

    /// Resolve VoxClaw peers by creating a brief NWConnection.
    /// This avoids bad/stale TXT `ip` records on hosts with multiple interfaces.
    private func resolvePeers() {
        for result in voxclawResults {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            if resolvedAddresses[name] != nil { continue }

            resolveEndpoint(result.endpoint, serviceName: name)
        }
    }

    /// Creates a brief NWConnection to resolve a Bonjour service endpoint to host:port.
    private nonisolated func resolveEndpoint(_ endpoint: NWEndpoint, serviceName: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let path = connection.currentPath,
                   let remote = path.remoteEndpoint,
                   case .hostPort(let host, let port) = remote {
                    let hostStr = "\(host)"
                    let portVal = port.rawValue
                    Task { @MainActor [weak self] in
                        self?.resolvedAddresses[serviceName] = (host: hostStr, port: portVal)
                        self?.rebuildPeers()
                        Log.network.info("Resolved \(serviceName, privacy: .public) → \(hostStr, privacy: .public):\(portVal, privacy: .public)")
                    }
                }
                connection.cancel()
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global())
    }

    private func extractTXTMetadata(from result: NWBrowser.Result) -> (host: String?, port: UInt16?) {
        guard case .bonjour(let txtRecord) = result.metadata else { return (nil, nil) }
        let rawHost = NetworkListener.readTXTValue(txtRecord, key: "ip")
        let host = (rawHost?.isEmpty == true) ? nil : rawHost
        let portStr = NetworkListener.readTXTValue(txtRecord, key: "port")
        let port = portStr.flatMap { UInt16($0) }
        return (host, port)
    }
}
