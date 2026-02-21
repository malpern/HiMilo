import Foundation
import SwiftUI

extension Notification.Name {
    static let voxClawOpenAIAuthFailed = Notification.Name("voxclaw.openaiAuthFailed")
    static let voxClawOpenAIKeyMissing = Notification.Name("voxclaw.openaiKeyMissing")
}

enum VoxClawNotificationUserInfo {
    static let openAIAuthErrorMessage = "openaiAuthErrorMessage"
}

enum SessionState: Sendable {
    case idle
    case loading
    case playing
    case paused
    case finished
}

@Observable
@MainActor
final class AppState {
    var sessionState: SessionState = .idle
    var words: [String] = []
    var currentWordIndex: Int = 0
    var isPaused: Bool = false
    var audioOnly: Bool = false
    var isListening: Bool = false
    var feedbackText: String? = nil
    var inputText: String = ""
    var autoClosedInstancesOnLaunch: Int = 0

    var isActive: Bool {
        switch sessionState {
        case .playing, .paused, .loading:
            return true
        default:
            return false
        }
    }

    func reset() {
        sessionState = .idle
        words = []
        currentWordIndex = 0
        isPaused = false
        feedbackText = nil
        inputText = ""
    }
}
