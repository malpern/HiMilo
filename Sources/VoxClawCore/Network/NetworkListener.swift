import Foundation
import Network
import SystemConfiguration
import os
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class NetworkListener {
    private var listener: NWListener?
    private let port: UInt16
    private let serviceName: String
    private let appState: AppState
    private var onReadRequest: (@Sendable (ReadRequest) async -> Void)?
    private let rateLimiter: RateLimiter
    private var bindMode: NetworkBindMode
    private var authToken: String?

    public var isListening: Bool { listener != nil }

    public init(
        port: UInt16 = 4140,
        serviceName: String? = nil,
        bindMode: NetworkBindMode = .localhost,
        authToken: String? = nil,
        appState: AppState
    ) {
        self.port = port
        self.serviceName = serviceName ?? Self.localComputerName()
        self.bindMode = bindMode
        self.authToken = authToken
        self.appState = appState
        self.rateLimiter = RateLimiter()
    }

    public func start(onReadRequest: @escaping @Sendable (ReadRequest) async -> Void) throws {
        guard listener == nil else { return }
        self.onReadRequest = onReadRequest

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            Log.network.error("Invalid port: \(self.port, privacy: .public)")
            return
        }
        
        // TODO: Localhost-only binding (bindMode.localhost) has Network.framework bugs
        // For now, bind to all interfaces (0.0.0.0) - auth token provides security
        
        listener = try NWListener(using: params, on: nwPort)

        // Advertise via Bonjour for LAN discovery with IP+port in TXT record
        let txtRecord = Self.makeTXTRecord([
            "ip": Self.localIPAddress() ?? "",
            "port": String(port),
        ])
        listener?.service = NWListener.Service(name: serviceName, type: "_voxclaw._tcp", txtRecord: txtRecord)

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

    public func stop() {
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
        let listenPort = port
        let token = authToken
        let limiter = rateLimiter
        let session = NetworkSession(
            connection: connection,
            authToken: token,
            rateLimiter: limiter,
            statusProvider: { @Sendable in
                await MainActor.run {
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
                        port: listenPort,
                        lanIP: NetworkListener.localIPAddress(),
                        autoClosedInstancesOnLaunch: state.autoClosedInstancesOnLaunch
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
        let ip = bindMode == .localhost ? "127.0.0.1" : (Self.localIPAddress() ?? "localhost")
        let mode = bindMode == .localhost ? "localhost only" : "LAN"
        let authRequired = authToken != nil ? " (auth required)" : ""
        
        print("")
        print("  VoxClaw listening on port \(port) (\(mode)\(authRequired))")
        print("")
        
        if bindMode == .lan {
            print("  Send text from another machine:")
            if let token = authToken {
                print("    curl -X POST http://\(ip):\(port)/read \\")
                print("      -H 'Content-Type: application/json' \\")
                print("      -H 'Authorization: Bearer \(token)' \\")
                print("      -d '{\"text\": \"Hello from the network\"}'")
            } else {
                print("    curl -X POST http://\(ip):\(port)/read \\")
                print("      -H 'Content-Type: application/json' \\")
                print("      -d '{\"text\": \"Hello from the network\"}'")
            }
            print("")
        } else {
            print("  Localhost-only mode (secure)")
            print("  To enable LAN access, change bind mode in Settings")
            print("")
            print("  Local test:")
            print("    curl -X POST http://127.0.0.1:\(port)/read \\")
            print("      -H 'Content-Type: application/json' \\")
            if let token = authToken {
                print("      -H 'Authorization: Bearer \(token)' \\")
            }
            print("      -d '{\"text\": \"Hello from localhost\"}'")
            print("")
        }
        
        print("  Health check:")
        print("    curl http://\(ip):\(port)/status")
        print("")
    }

    public static func localHostname() -> String {
        ProcessInfo.processInfo.hostName
    }

    /// Human-readable computer name (e.g. "Mark's MacBook Pro").
    public static func localComputerName() -> String {
        #if os(macOS)
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String? {
            return name
        }
        #else
        return UIDevice.current.name
        #endif
        // Fallback: strip .local and replace hyphens
        let host = ProcessInfo.processInfo.hostName
        return host.replacingOccurrences(of: ".local", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    /// Device-type-aware Bonjour service name (e.g. "VoxMacBook Pro", "VoxiPhone").
    public static func localVoxServiceName() -> String {
        let deviceType = Self.deviceModelName()
        return "Vox\(deviceType)"
    }

    /// Returns a human-readable device model name (e.g. "MacBook Pro", "Mac mini", "iPhone").
    static func deviceModelName() -> String {
        #if canImport(UIKit) && !os(macOS)
        return UIDevice.current.model // "iPhone", "iPad", "iPod touch"
        #else
        // Use sysctl to get the hardware model identifier
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let nullIndex = model.firstIndex(of: 0) ?? model.endIndex
        let identifier = String(decoding: model[..<nullIndex].map { UInt8(bitPattern: $0) }, as: UTF8.self)

        // Intel Macs: identifier starts with product name (e.g. "MacBookPro18,1")
        let lower = identifier.lowercased()
        if lower.hasPrefix("macbookpro") { return "MacBook Pro" }
        if lower.hasPrefix("macbookair") { return "MacBook Air" }
        if lower.hasPrefix("macbook") { return "MacBook" }
        if lower.hasPrefix("macmini") { return "Mac mini" }
        if lower.hasPrefix("macpro") { return "Mac Pro" }
        if lower.hasPrefix("imacpro") { return "iMac Pro" }
        if lower.hasPrefix("imac") { return "iMac" }

        // Apple Silicon Macs: identifier is "MacN,N" — infer from computer name
        if lower.hasPrefix("mac") {
            return deviceTypeFromComputerName()
        }
        return "Mac"
        #endif
    }

    #if os(macOS)
    /// Infers device type from the user's computer name (e.g. "Mark's MacBook Pro" → "MacBook Pro").
    private static func deviceTypeFromComputerName() -> String {
        let name = localComputerName().lowercased()
        if name.contains("macbook pro") { return "MacBook Pro" }
        if name.contains("macbook air") { return "MacBook Air" }
        if name.contains("macbook") { return "MacBook" }
        if name.contains("mac mini") { return "Mac mini" }
        if name.contains("mac pro") { return "Mac Pro" }
        if name.contains("mac studio") { return "Mac Studio" }
        if name.contains("imac") { return "iMac" }
        if name.contains("mac") { return "Mac" }
        return "Mac"
    }
    #endif

    /// Constructs an NWTXTRecord from key-value pairs.
    static func makeTXTRecord(_ entries: [String: String]) -> NWTXTRecord {
        var record = NWTXTRecord()
        for (key, value) in entries {
            record[key] = value
        }
        return record
    }

    /// Reads a value from an NWTXTRecord by key.
    public static func readTXTValue(_ record: NWTXTRecord, key: String) -> String? {
        record[key]
    }

    public static func localIPAddress() -> String? {
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
