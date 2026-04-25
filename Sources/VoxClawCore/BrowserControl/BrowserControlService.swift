import Foundation
import Network

#if os(macOS)
final class BrowserControlService: @unchecked Sendable {
    static let shared = BrowserControlService()

    private let queue = DispatchQueue(label: "com.malpern.voxclaw.browser-control")
    private var listener: NWListener?
    private var allConnections: [ObjectIdentifier: BrowserControlPeerConnection] = [:]
    private var browserConnections: [ObjectIdentifier: BrowserControlPeerConnection] = [:]
    private var controllerConnections: [ObjectIdentifier: BrowserControlPeerConnection] = [:]
    private var pendingRoutes: [String: BrowserControlPeerConnection] = [:]

    private init() {}

    func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    private func startLocked() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(IPv4Address(BrowserControlRuntime.hostName)!),
                port: NWEndpoint.Port(rawValue: BrowserControlRuntime.servicePort)!
            )

            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Log.playback.info("Browser control service ready on \(BrowserControlRuntime.hostName, privacy: .public):\(BrowserControlRuntime.servicePort, privacy: .public)")
                case .failed(let error):
                    Log.playback.error("Browser control service failed: \(error.localizedDescription, privacy: .public)")
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Log.playback.error("Failed to start browser control service: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func accept(_ connection: NWConnection) {
        let peer = BrowserControlPeerConnection(connection: connection, queue: queue)
        allConnections[peer.identifier] = peer
        Log.playback.info("Accepted browser-control peer (total=\(self.allConnections.count, privacy: .public))")
        peer.onMessage = { [weak self, weak peer] message in
            guard let self, let peer else { return }
            self.handle(message, from: peer)
        }
        peer.onClose = { [weak self, weak peer] in
            guard let self, let peer else { return }
            self.remove(peer)
        }
        connection.stateUpdateHandler = { [weak self, weak peer] state in
            guard let self, let peer else { return }
            switch state {
            case .failed, .cancelled:
                Log.playback.info("Peer connection ended (\(String(describing: state), privacy: .public)); pruning")
                self.remove(peer)
            default:
                break
            }
        }
        connection.start(queue: queue)
        peer.startReceiving()
    }

    private func handle(_ message: BrowserControlMessage, from peer: BrowserControlPeerConnection) {
        switch message.type {
        case .registerBrowserBridge:
            browserConnections[peer.identifier] = peer
            Log.playback.info("Browser bridge connected (total=\(self.browserConnections.count, privacy: .public))")
        case .pauseIfPlaying, .resume, .ping:
            controllerConnections[peer.identifier] = peer
            guard let browser = pickLiveBrowser() else {
                let warning = "Load the VoxClaw browser extension in Chrome or Chrome Canary to pause background YouTube tabs."
                peer.send(BrowserControlMessage(id: message.id, type: .error, ok: false, warning: warning))
                return
            }
            pendingRoutes[message.id] = peer
            Log.playback.info("Routing \(message.type.rawValue, privacy: .public) id=\(message.id, privacy: .public) to browser bridge")
            browser.send(message)
        case .pauseResult, .resumeResult, .pong, .error:
            guard let controller = pendingRoutes.removeValue(forKey: message.id) else { return }
            controller.send(message)
        }
    }

    private func pickLiveBrowser() -> BrowserControlPeerConnection? {
        let stale = browserConnections.filter { _, peer in
            switch peer.connection.state {
            case .failed, .cancelled:
                return true
            default:
                return false
            }
        }
        for (id, _) in stale {
            browserConnections.removeValue(forKey: id)
        }
        if !stale.isEmpty {
            Log.playback.info("Pruned \(stale.count, privacy: .public) stale browser bridge(s)")
        }
        return browserConnections.values.sorted { $0.createdAt > $1.createdAt }.first
    }

    private func remove(_ peer: BrowserControlPeerConnection) {
        allConnections.removeValue(forKey: peer.identifier)
        browserConnections.removeValue(forKey: peer.identifier)
        controllerConnections.removeValue(forKey: peer.identifier)
        pendingRoutes = pendingRoutes.filter { $0.value.identifier != peer.identifier }
    }
}

private final class BrowserControlPeerConnection: @unchecked Sendable {
    let connection: NWConnection
    let queue: DispatchQueue
    let identifier: ObjectIdentifier
    let createdAt: Date = Date()
    var onMessage: ((BrowserControlMessage) -> Void)?
    var onClose: (() -> Void)?
    private var buffer = Data()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
        self.identifier = ObjectIdentifier(connection)
    }

    func startReceiving() {
        receive()
    }

    func send(_ message: BrowserControlMessage) {
        do {
            var data = try encoder.encode(message)
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    Log.playback.error("Browser control send failed: \(error.localizedDescription, privacy: .public)")
                }
            })
        } catch {
            Log.playback.error("Failed to encode browser control message: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let error {
                Log.playback.error("Browser control receive failed: \(error.localizedDescription, privacy: .public)")
                self.onClose?()
                return
            }
            if let content, !content.isEmpty {
                self.buffer.append(content)
                self.drainBuffer()
            }
            if isComplete {
                self.onClose?()
                return
            }
            self.receive()
        }
    }

    private func drainBuffer() {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else { continue }
            do {
                let message = try decoder.decode(BrowserControlMessage.self, from: line)
                onMessage?(message)
            } catch {
                Log.playback.error("Failed to decode browser control line: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
