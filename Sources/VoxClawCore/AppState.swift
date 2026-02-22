import Foundation
import SwiftUI

extension Notification.Name {
    public static let voxClawOpenAIAuthFailed = Notification.Name("voxclaw.openaiAuthFailed")
    public static let voxClawOpenAIKeyMissing = Notification.Name("voxclaw.openaiKeyMissing")
}

public enum VoxClawNotificationUserInfo {
    public static let openAIAuthErrorMessage = "openaiAuthErrorMessage"
}

public enum SessionState: Sendable {
    case idle
    case loading
    case playing
    case paused
    case finished
}

/// Which timing algorithm is currently driving word highlighting.
public enum TimingSource: Sendable {
    case cadence      // Fixed per-character estimate (initial)
    case aligner      // On-device speech recognition partial results
    case proportional // Duration-proportional heuristic (stream complete)
    case aligned      // Final aligned timings from speech recognizer
}

@Observable
@MainActor
public final class AppState {
    public var sessionState: SessionState = .idle
    public var words: [String] = []
    public var currentWordIndex: Int = 0
    public var isPaused: Bool = false
    public var audioOnly: Bool = false
    public var isListening: Bool = false
    public var feedbackText: String? = nil
    public var speedIndicatorText: String? = nil
    public var timingSource: TimingSource = .cadence
    public var inputText: String = ""
    public var autoClosedInstancesOnLaunch: Int = 0

    public var isActive: Bool {
        switch sessionState {
        case .playing, .paused, .loading:
            return true
        default:
            return false
        }
    }

    public init() {}

    public func reset() {
        sessionState = .idle
        words = []
        currentWordIndex = 0
        isPaused = false
        feedbackText = nil
        speedIndicatorText = nil
        timingSource = .cadence
        inputText = ""
    }
}
