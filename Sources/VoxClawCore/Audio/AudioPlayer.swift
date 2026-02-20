import AVFoundation
import Foundation
import os

@MainActor
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 24000
    private let format: AVAudioFormat

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
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        Log.audio.info("Audio engine starting")
        try engine.start()
        playerNode.play()
        isPlaying = true
    }

    func scheduleChunk(_ pcmData: Data) {
        let sampleCount = pcmData.count / 2 // 16-bit = 2 bytes per sample

        guard sampleCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)

        // Convert Int16 LE PCM to Float32
        let floatData = buffer.floatChannelData![0]
        pcmData.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floatData[i] = Float(int16Buffer[i]) / Float(Int16.max)
            }
        }

        totalBytesScheduled += pcmData.count
        Log.audio.debug("Scheduled chunk: \(sampleCount, privacy: .public) samples, totalDuration=\(self.totalDuration, privacy: .public)s")
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
