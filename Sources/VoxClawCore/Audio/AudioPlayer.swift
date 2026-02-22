import AVFoundation
import Foundation
import os

@MainActor
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitchNode = AVAudioUnitTimePitch()
    private let sampleRate: Double = 24000
    private let format: AVAudioFormat

    var playbackRate: Float {
        get { timePitchNode.rate }
        set { timePitchNode.rate = newValue }
    }

    private var totalBytesScheduled: Int = 0
    private var isPlaying = false
    private var onFinished: (() -> Void)?

    enum AudioPlayerError: Error, CustomStringConvertible {
        case formatInitFailed
        var description: String { "Failed to create audio format (Float32, 24kHz, mono)" }
    }

    var totalDuration: Double {
        // 16-bit mono = 2 bytes per sample
        Double(totalBytesScheduled) / 2.0 / sampleRate
    }

    var currentTime: Double {
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    init() throws {
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioPlayerError.formatInitFailed
        }
        format = fmt

        engine.attach(playerNode)
        engine.attach(timePitchNode)
        engine.connect(playerNode, to: timePitchNode, format: format)
        engine.connect(timePitchNode, to: engine.mainMixerNode, format: format)
    }

    /// Start the audio engine without playing. Call `play()` after buffering initial chunks.
    func prepare() throws {
        Log.audio.info("Audio engine preparing")
        try engine.start()
    }

    /// Begin playback. Call after scheduling initial buffered chunks.
    func play() {
        Log.audio.info("Audio playback starting")
        playerNode.play()
        isPlaying = true
    }

    /// Convert 16-bit signed LE PCM data to a Float32 `AVAudioPCMBuffer`.
    nonisolated static func pcmBuffer(from pcmData: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleCount = pcmData.count / 2 // 16-bit = 2 bytes per sample
        guard sampleCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        guard let floatData = buffer.floatChannelData?[0] else { return nil }
        pcmData.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floatData[i] = Float(int16Buffer[i]) / Float(Int16.max)
            }
        }
        return buffer
    }

    func scheduleChunk(_ pcmData: Data) {
        guard let buffer = Self.pcmBuffer(from: pcmData, format: format) else {
            Log.audio.warning("Failed to convert PCM chunk (\(pcmData.count) bytes) to audio buffer")
            return
        }

        totalBytesScheduled += pcmData.count
        Log.audio.debug("Scheduled chunk: \(buffer.frameLength, privacy: .public) samples, totalDuration=\(self.totalDuration, privacy: .public)s")
        playerNode.scheduleBuffer(buffer)
    }

    func scheduleEnd(onFinished: @escaping @Sendable () -> Void) {
        self.onFinished = onFinished
        // Schedule an empty completion handler to detect when playback finishes
        guard let emptyBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1) else { return }
        emptyBuffer.frameLength = 0
        playerNode.scheduleBuffer(emptyBuffer) { [weak self] in
            Task { @MainActor in
                self?.onFinished?()
            }
        }
    }

    func pause() {
        Log.audio.info("Audio paused at \(self.currentTime, privacy: .public)s")
        playerNode.pause()
        isPlaying = false
    }

    func resume() {
        Log.audio.info("Audio resumed at \(self.currentTime, privacy: .public)s")
        playerNode.play()
        isPlaying = true
    }

    func stop() {
        Log.audio.info("Audio engine stopped")
        playerNode.stop()
        engine.stop()
        isPlaying = false
        totalBytesScheduled = 0
        onFinished = nil
    }
}
