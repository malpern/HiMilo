import Foundation

public struct PlaybackSnapshot: Sendable, Equatable {
    public let isEmpty: Bool
    public init(isEmpty: Bool = false) { self.isEmpty = isEmpty }
}

@MainActor
public protocol ExternalPlaybackControlling {
    func pauseIfPlaying() -> PlaybackSnapshot?
    func resume(_ snapshot: PlaybackSnapshot)
}

@MainActor
public final class ExternalPlaybackController: ExternalPlaybackControlling {
    public init() {}
    public func pauseIfPlaying() -> PlaybackSnapshot? { nil }
    public func resume(_ snapshot: PlaybackSnapshot) {}
}
