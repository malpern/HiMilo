import Foundation
import Network

@MainActor
final class NetworkListener {
    private var listener: NWListener?
    private let port: UInt16
    private let appState: AppState
    private var onTextReceived: (@Sendable (String) async -> Void)?

    var isListening: Bool { listener != nil }

    init(port: UInt16 = 4140, appState: AppState) {
        self.port = port
        self.appState = appState
    }

    func start(onTextReceived: @escaping @Sendable (String) async -> Void) throws {
        guard listener == nil else { return }
        self.onTextReceived = onTextReceived

        let params = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        // Advertise via Bonjour for LAN discovery
        listener?.service = NWListener.Service(name: "HeyMilo", type: "_milo._tcp")

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
        printListeningInfo()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        appState.isListening = false
        onTextReceived = nil
        print("HeyMilo listener stopped")
    }

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("HeyMilo HTTP listener ready")
        case .failed(let error):
            print("Network listener failed: \(error)")
            stop()
        case .cancelled:
            break
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let session = NetworkSession(connection: connection) { [weak self] text in
            await self?.onTextReceived?(text)
        }
        session.start()
    }

    private func printListeningInfo() {
        let ip = Self.localIPAddress() ?? "localhost"
        print("")
        print("  HeyMilo listening on port \(port)")
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
