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
        print("HeyMilo listening on port \(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        appState.isListening = false
        onTextReceived = nil
    }

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("Network listener ready on port \(port)")
        case .failed(let error):
            print("Network listener failed: \(error)")
            stop()
        case .cancelled:
            print("Network listener cancelled")
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
}
