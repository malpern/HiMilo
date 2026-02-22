import AVFoundation
import Foundation

@Observable
@MainActor
final class BackgroundAudioKeepAlive {
    private(set) var isActive = false
    private(set) var didTimeout = false

    private var player: AVAudioPlayer?
    private var timeoutTimer: Timer?

    private static let timeoutInterval: TimeInterval = 30 * 60 // 30 minutes

    func start() {
        guard !isActive else { return }
        didTimeout = false

        if player == nil {
            player = Self.makeSilentPlayer()
        }
        player?.play()
        isActive = true
        startTimeoutTimer()
    }

    func stop() {
        player?.stop()
        isActive = false
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    func resetTimeout() {
        didTimeout = false
        guard isActive else { return }
        startTimeoutTimer()
    }

    // MARK: - Private

    private func startTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.timeoutInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTimeout()
            }
        }
    }

    private func handleTimeout() {
        didTimeout = true
        stop()
    }

    /// Generate a tiny silent WAV in memory — no bundled audio file needed.
    private static func makeSilentPlayer() -> AVAudioPlayer? {
        let sampleRate: Double = 44100
        let durationSeconds: Double = 1.0
        let channels: Int = 1
        let bitsPerSample: Int = 16
        let numSamples = Int(sampleRate * durationSeconds)
        let dataSize = numSamples * channels * (bitsPerSample / 8)

        var wav = Data()

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(uint32LE: UInt32(36 + dataSize))
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(uint32LE: 16)                          // chunk size
        wav.append(uint16LE: 1)                           // PCM format
        wav.append(uint16LE: UInt16(channels))
        wav.append(uint32LE: UInt32(sampleRate))
        wav.append(uint32LE: UInt32(sampleRate * Double(channels * bitsPerSample / 8))) // byte rate
        wav.append(uint16LE: UInt16(channels * bitsPerSample / 8)) // block align
        wav.append(uint16LE: UInt16(bitsPerSample))

        // data chunk — all zeros = silence
        wav.append(contentsOf: "data".utf8)
        wav.append(uint32LE: UInt32(dataSize))
        wav.append(Data(count: dataSize))

        do {
            let player = try AVAudioPlayer(data: wav)
            player.numberOfLoops = -1 // loop forever
            player.volume = 0.01      // near-silent
            return player
        } catch {
            print("BackgroundAudioKeepAlive: failed to create player: \(error)")
            return nil
        }
    }
}

// MARK: - Data helpers for WAV construction

private extension Data {
    mutating func append(uint16LE value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func append(uint32LE value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
