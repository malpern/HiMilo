import Foundation
import Network
import os

@MainActor
final class NetworkListener {
    private var listener: NWListener?
    private let port: UInt16
    private let serviceName: String?
    private let appState: AppState
    private var onReadRequest: (@Sendable (ReadRequest) async -> Void)?

    var isListening: Bool { listener != nil }

    init(port: UInt16 = 4140, serviceName: String? = "VoxClaw", appState: AppState) {
        self.port = port
        self.serviceName = serviceName
        self.appState = appState
    }

    func start(onReadRequest: @escaping @Sendable (ReadRequest) async -> Void) throws {
        guard listener == nil else { return }
        self.onReadRequest = onReadRequest

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        // Advertise via Bonjour for LAN discovery
        if let serviceName {
            listener?.service = NWListener.Service(name: serviceName, type: "_voxclaw._tcp")
        }

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleStateUpdate(state)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }

        listener?.start(queue: .main)
        appState.isListening = true
        let listenPort = port
        Log.network.info("Listener starting on port \(listenPort, privacy: .public)")
        printListeningInfo()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        appState.isListening = false
        onReadRequest = nil
        Log.network.info("Listener stopped")
        print("VoxClaw listener stopped")
    }

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            Log.network.info("Listener ready on port \(self.port, privacy: .public)")
            print("VoxClaw HTTP listener ready")
        case .failed(let error):
            Log.network.error("Listener failed: \(error)")
            print("Network listener failed: \(error)")
            stop()
        case .cancelled:
            break
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        Log.network.debug("New connection from \(String(describing: connection.endpoint), privacy: .public)")
        let state = appState
        let session = NetworkSession(
            connection: connection,
            statusProvider: { @Sendable in
                // AppState is @MainActor — capture current values synchronously from main
                MainActor.assumeIsolated {
                    let reading = state.isActive
                    let sessionState: String
                    switch state.sessionState {
                    case .idle: sessionState = "idle"
                    case .loading: sessionState = "loading"
                    case .playing: sessionState = "playing"
                    case .paused: sessionState = "paused"
                    case .finished: sessionState = "finished"
                    }
                    return (
                        reading: reading,
                        state: sessionState,
                        wordCount: state.words.count,
                        port: self.port,
                        lanIP: Self.localIPAddress()
                    )
                }
            },
            onReadRequest: { [weak self] request in
                await self?.onReadRequest?(request)
            }
        )
        session.start()
    }

    private func printListeningInfo() {
        let ip = Self.localIPAddress() ?? "localhost"
        print("")
        print("  VoxClaw listening on port \(port)")
        print("")
        print("  Send text from another machine:")
        print("    curl -X POST http://\(ip):\(port)/read \\")
        print("      -H 'Content-Type: application/json' \\")
        print("      -d '{\"text\": \"Hello from the network\"}'")
        print("")
        print("  Or with plain text:")
        print("    curl -X POST http://\(ip):\(port)/read -d 'Hello from the network'")
        print("")
        print("  Health check:")
        print("    curl http://\(ip):\(port)/status")
        print("")
    }

    static func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let addr = ptr.pointee
            guard addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: addr.ifa_name)
            // Prefer en0 (Wi-Fi) or en1, skip loopback
            guard name.hasPrefix("en") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr.ifa_addr, socklen_t(addr.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            )
            if result == 0 {
                let nullTermIndex = hostname.firstIndex(of: 0) ?? hostname.endIndex
                return String(decoding: hostname[..<nullTermIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        return nil
    }
}
