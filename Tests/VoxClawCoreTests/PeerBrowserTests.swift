@testable import VoxClawCore
import Foundation
import Testing

struct PeerBrowserTests {
    @Test func voxclawBaseURLSupportsIPv4() {
        let peer = DiscoveredPeer(
            id: "voxclaw.ipv4",
            name: "VoxMac",
            app: .voxclaw,
            host: "192.168.1.25",
            port: 4140
        )

        #expect(peer.baseURL == "http://192.168.1.25:4140")
        #expect(URL(string: "\(peer.baseURL ?? "")/read") != nil)
    }

    @Test func voxclawBaseURLBracketsIPv6() {
        let peer = DiscoveredPeer(
            id: "voxclaw.ipv6",
            name: "VoxiPhone",
            app: .voxclaw,
            host: "fe80::1234",
            port: 4140
        )

        #expect(peer.baseURL == "http://[fe80::1234]:4140")
        #expect(URL(string: "\(peer.baseURL ?? "")/read") != nil)
    }

    @Test func voxclawBaseURLBracketsScopedIPv6() {
        let peer = DiscoveredPeer(
            id: "voxclaw.ipv6.scoped",
            name: "VoxiPhone",
            app: .voxclaw,
            host: "fe80::abcd%en0",
            port: 4140
        )

        #expect(peer.baseURL == "http://[fe80::abcd%en0]:4140")
        let url = URL(string: "\(peer.baseURL ?? "")/read")
        #expect(url != nil)
        #expect(url?.absoluteString.contains("%25en0") == true)
    }

    @Test func voxclawBaseURLStripsInvalidIPv4Scope() {
        let peer = DiscoveredPeer(
            id: "voxclaw.ipv4.scoped",
            name: "VoxMac",
            app: .voxclaw,
            host: "192.168.1.228%en0",
            port: 4140
        )

        #expect(peer.baseURL == "http://192.168.1.228:4140")
        #expect(URL(string: "\(peer.baseURL ?? "")/read") != nil)
    }

    @Test func voxclawBaseURLKeepsPreBracketedIPv6() {
        let peer = DiscoveredPeer(
            id: "voxclaw.ipv6.bracketed",
            name: "VoxMac",
            app: .voxclaw,
            host: "[fe80::beef]",
            port: 4140
        )

        #expect(peer.baseURL == "http://[fe80::beef]:4140")
        #expect(URL(string: "\(peer.baseURL ?? "")/read") != nil)
    }

    @Test func nonVoxclawPeerHasNoBaseURL() {
        let peer = DiscoveredPeer(
            id: "openclaw.1",
            name: "OpenClaw",
            app: .openclaw,
            host: "192.168.1.100",
            port: 4140
        )

        #expect(peer.baseURL == nil)
    }
}
