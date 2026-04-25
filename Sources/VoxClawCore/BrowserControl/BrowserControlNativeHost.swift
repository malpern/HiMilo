import Foundation
import Network

#if os(macOS)
private func hostTrace(_ message: @autoclosure () -> String) {
    FileHandle.standardError.write(Data("[native-host \(ProcessInfo.processInfo.processIdentifier)] \(message())\n".utf8))
}

enum BrowserControlNativeHostRunner {
    static func run() throws {
        hostTrace("run() start")
        let port: BrowserControlNativeHostPort
        do {
            port = try connectToService()
            hostTrace("connected to service")
        } catch {
            hostTrace("connectToService failed: \(error)")
            throw error
        }
        let serviceConnection = port.connection
        let stdinHandle = FileHandle.standardInput
        let stdoutHandle = FileHandle.standardOutput
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        do {
            try port.send(BrowserControlMessage(type: .registerBrowserBridge))
            hostTrace("sent registerBrowserBridge")
        } catch {
            hostTrace("registerBrowserBridge send failed: \(error)")
            throw error
        }

        let serviceToExtension = Thread {
            hostTrace("service->extension thread started")
            do {
                while let line = try port.readLine() {
                    hostTrace("from service: \(line.count) bytes")
                    let message = try decoder.decode(BrowserControlMessage.self, from: line)
                    try writeNativeMessage(message, to: stdoutHandle, encoder: encoder)
                    hostTrace("wrote native message to stdout type=\(message.type.rawValue) id=\(message.id)")
                }
                hostTrace("service readLine returned nil (TCP closed)")
            } catch {
                hostTrace("service read error: \(error)")
                Log.playback.error("Native host service read failed: \(error.localizedDescription, privacy: .public)")
            }
            serviceConnection.cancel()
            hostTrace("exiting(0) from service thread")
            exit(0)
        }
        serviceToExtension.start()

        hostTrace("main loop: reading stdin")
        while let message = try readNativeMessage(from: stdinHandle, decoder: decoder) {
            hostTrace("from chrome: type=\(message.type.rawValue) id=\(message.id)")
            try port.send(message)
        }
        hostTrace("stdin EOF; main returning")
    }

    private static func connectToService() throws -> BrowserControlNativeHostPort {
        guard let portNumber = NWEndpoint.Port(rawValue: BrowserControlRuntime.servicePort) else {
            throw NSError(domain: "BrowserControlNativeHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid browser control port"])
        }
        let parameters = NWParameters.tcp
        if let tcp = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            tcp.version = .v4
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(BrowserControlRuntime.hostName),
            port: portNumber,
            using: parameters
        )

        let readySemaphore = DispatchSemaphore(value: 0)
        let stateBox = NativeHostStateBox()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                stateBox.ready = true
                readySemaphore.signal()
            case .waiting(let error), .failed(let error):
                stateBox.error = error
                readySemaphore.signal()
            case .cancelled:
                stateBox.cancelled = true
                readySemaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .utility))

        let timeout: DispatchTime = .now() + .seconds(3)
        if readySemaphore.wait(timeout: timeout) == .timedOut {
            connection.cancel()
            throw NSError(domain: "BrowserControlNativeHost", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Timed out connecting to VoxClaw (is the app running?)"
            ])
        }
        if let error = stateBox.error {
            connection.cancel()
            throw error
        }
        if !stateBox.ready {
            connection.cancel()
            throw NSError(domain: "BrowserControlNativeHost", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Browser control connection did not become ready"
            ])
        }
        connection.stateUpdateHandler = nil
        return BrowserControlNativeHostPort(connection: connection)
    }

    private static func readNativeMessage(from handle: FileHandle, decoder: JSONDecoder) throws -> BrowserControlMessage? {
        let header = try handle.read(upToCount: 4) ?? Data()
        guard header.count == 4 else { return nil }

        let length = header.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        guard length > 0 else { return nil }

        let payload = try handle.read(upToCount: Int(length)) ?? Data()
        guard payload.count == Int(length) else { return nil }
        return try decoder.decode(BrowserControlMessage.self, from: payload)
    }

    private static func writeNativeMessage(
        _ message: BrowserControlMessage,
        to handle: FileHandle,
        encoder: JSONEncoder
    ) throws {
        let payload = try encoder.encode(message)
        var length = UInt32(payload.count).littleEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: payload)
    }
}

private final class BrowserControlNativeHostPort: @unchecked Sendable {
    let connection: NWConnection
    private var buffer = Data()
    private let semaphore = DispatchSemaphore(value: 0)
    private var pendingError: Error?
    private var isClosed = false

    init(connection: NWConnection) {
        self.connection = connection
        scheduleReceive()
    }

    func send(_ message: BrowserControlMessage) throws {
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)
        let semaphore = DispatchSemaphore(value: 0)
        let errorBox = NativeHostErrorBox()
        connection.send(content: data, completion: .contentProcessed { error in
            errorBox.error = error
            semaphore.signal()
        })
        semaphore.wait()
        if let sendError = errorBox.error { throw sendError }
    }

    func readLine() throws -> Data? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer.prefix(upTo: newlineIndex))
                buffer.removeSubrange(...newlineIndex)
                return line.isEmpty ? nil : line
            }
            semaphore.wait()
            if let pendingError { throw pendingError }
            if isClosed {
                return nil
            }
        }
    }

    private func scheduleReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.pendingError = error
                self.semaphore.signal()
                return
            }
            if let content, !content.isEmpty {
                self.buffer.append(content)
                self.semaphore.signal()
            }
            if isComplete {
                self.isClosed = true
                self.connection.cancel()
                self.semaphore.signal()
                return
            }
            self.scheduleReceive()
        }
    }
}

private final class NativeHostStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _ready = false
    private var _cancelled = false
    private var _error: Error?

    var ready: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _ready }
        set { lock.lock(); _ready = newValue; lock.unlock() }
    }
    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); _cancelled = newValue; lock.unlock() }
    }
    var error: Error? {
        get { lock.lock(); defer { lock.unlock() }; return _error }
        set { lock.lock(); _error = newValue; lock.unlock() }
    }
}

private final class NativeHostErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _error: Error?

    var error: Error? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _error
        }
        set {
            lock.lock()
            _error = newValue
            lock.unlock()
        }
    }
}
#endif
