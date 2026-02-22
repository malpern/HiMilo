@testable import VoxClawCore
import AVFoundation
import Testing

struct AudioPlayerTests {
    private static var format: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!
    }

    // MARK: - pcmBuffer

    @Test func pcmBufferConvertsValidData() {
        // 4 samples of 16-bit PCM = 8 bytes
        let samples: [Int16] = [0, 16383, -16384, 32767]
        let data = samples.withUnsafeBufferPointer {
            Data(buffer: $0)
        }
        let buffer = AudioPlayer.pcmBuffer(from: data, format: Self.format)
        #expect(buffer != nil)
        #expect(buffer?.frameLength == 4)
    }

    @Test func pcmBufferReturnsNilForEmptyData() {
        let buffer = AudioPlayer.pcmBuffer(from: Data(), format: Self.format)
        #expect(buffer == nil)
    }

    @Test func pcmBufferReturnsNilForSingleByte() {
        // 1 byte is not a complete 16-bit sample
        let buffer = AudioPlayer.pcmBuffer(from: Data([0xFF]), format: Self.format)
        #expect(buffer == nil)
    }

    @Test func pcmBufferNormalizesToFloatRange() {
        // Int16.max should map to ~1.0
        let samples: [Int16] = [Int16.max]
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let buffer = AudioPlayer.pcmBuffer(from: data, format: Self.format)

        #expect(buffer != nil)
        if let floatData = buffer?.floatChannelData?[0] {
            let value = floatData[0]
            #expect(value > 0.99 && value <= 1.0)
        }
    }

    @Test func pcmBufferZeroSampleMapsToZero() {
        let samples: [Int16] = [0]
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let buffer = AudioPlayer.pcmBuffer(from: data, format: Self.format)

        #expect(buffer != nil)
        if let floatData = buffer?.floatChannelData?[0] {
            #expect(floatData[0] == 0.0)
        }
    }

    @Test func pcmBufferHandlesMultipleSamples() {
        let sampleCount = 2400 // 100ms of 24kHz audio
        let samples = [Int16](repeating: 1000, count: sampleCount)
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let buffer = AudioPlayer.pcmBuffer(from: data, format: Self.format)

        #expect(buffer != nil)
        #expect(buffer?.frameLength == AVAudioFrameCount(sampleCount))
    }
}
