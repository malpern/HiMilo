import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Curated voice pools used to auto-assign distinguishable voices to projects/agents.
public enum VoicePool {
    public static let openAI: [String] = [
        "alloy", "echo", "fable", "onyx", "nova", "shimmer", "ash", "sage", "coral"
    ]

    /// Well-known ElevenLabs public voice IDs. Users with custom libraries can override
    /// per-binding via Settings; this list just seeds first-contact assignments.
    public static let elevenLabs: [String] = [
        "21m00Tcm4TlvDq8ikWAM", // Rachel
        "AZnzlk1XvdvUeBnXmlld", // Domi
        "EXAVITQu4vr4xnSDxMaL", // Bella
        "ErXwobaYiN019PkySvjV", // Antoni
        "TxGEqnHWrfWFTfGW9XjX", // Josh
        "VR6AewLTigWG4xSOukaG", // Arnold
        "pNInz6obpgDQGcFmaJgB", // Adam
        "yoZ06aMxZJJ28mfd3POQ"  // Sam
    ]

    /// Preferred Apple voice identifiers, in priority order. Filtered against installed
    /// voices at runtime; if none are present, falls back to any en-* voices.
    public static let applePreferred: [String] = [
        "com.apple.voice.compact.en-US.Samantha",
        "com.apple.voice.compact.en-GB.Daniel",
        "com.apple.voice.compact.en-AU.Karen",
        "com.apple.voice.compact.en-IE.Moira",
        "com.apple.voice.enhanced.en-US.Alex",
        "com.apple.voice.compact.en-ZA.Tessa",
        "com.apple.voice.compact.en-US.Fred",
        "com.apple.voice.compact.en-US.Victoria"
    ]

    public static func apple() -> [String] {
        #if canImport(AVFoundation)
        let installed = Set(AVSpeechSynthesisVoice.speechVoices().map(\.identifier))
        let filtered = applePreferred.filter { installed.contains($0) }
        if !filtered.isEmpty { return filtered }
        let enVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map(\.identifier)
        return Array(enVoices.prefix(8))
        #else
        return applePreferred
        #endif
    }

    public static func voices(for engine: VoiceEngineType) -> [String] {
        switch engine {
        case .apple: return apple()
        case .openai: return openAI
        case .elevenlabs: return elevenLabs
        }
    }
}
