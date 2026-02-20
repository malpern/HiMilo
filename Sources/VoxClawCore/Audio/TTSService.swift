import Foundation
import os

actor TTSService {
    private let apiKey: String
    private let voice: String
    private let speed: Float
    private let model = "gpt-4o-mini-tts"

    init(apiKey: String, voice: String = "onyx", speed: Float = 1.0) {
        self.apiKey = apiKey
        self.voice = voice
        self.speed = speed
    }

    struct TTSError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    func streamPCM(text: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    Log.tts.info("TTS request: voice=\(self.voice, privacy: .public), model=\(self.model, privacy: .public), textLength=\(text.count, privacy: .public)")
                    let request = try buildRequest(text: text)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw TTSError(message: "Invalid response type")
                    }

                    Log.tts.info("TTS response: status=\(httpResponse.statusCode, privacy: .public)")

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await byte in bytes {
                            errorBody.append(Character(UnicodeScalar(byte)))
                            if errorBody.count > 1000 { break } // Don't accumulate huge error bodies
                        }
                        Log.tts.error("TTS API error: status=\(httpResponse.statusCode, privacy: .public)")
                        throw TTSError(message: Self.friendlyError(status: httpResponse.statusCode, body: errorBody))
                    }

                    // Stream in chunks of 4800 bytes (~100ms of 24kHz 16-bit mono)
                    let chunkSize = 4800
                    var buffer = Data()
                    var chunkCount = 0
                    var totalBytes = 0

                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            let chunk = buffer.prefix(chunkSize)
                            continuation.yield(Data(chunk))
                            buffer = Data(buffer.dropFirst(chunkSize))
                            chunkCount += 1
                            totalBytes += chunkSize
                            if chunkCount % 20 == 0 {
                                Log.tts.debug("TTS streaming: \(chunkCount, privacy: .public) chunks, \(totalBytes, privacy: .public) bytes")
                            }
                        }
                    }

                    // Yield remaining bytes
                    if !buffer.isEmpty {
                        totalBytes += buffer.count
                        continuation.yield(buffer)
                    }

                    Log.tts.info("TTS complete: \(chunkCount, privacy: .public) chunks, \(totalBytes, privacy: .public) total bytes")
                    continuation.finish()
                } catch {
                    Log.tts.error("TTS stream error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func friendlyError(status: Int, body: String) -> String {
        switch status {
        case 401:
            return "Invalid OpenAI API key. Check your key in Settings or Keychain."
        case 429:
            return "OpenAI rate limit reached. Please wait a moment and try again."
        case 400:
            return "OpenAI rejected the request. The text may be too long or contain unsupported content."
        case 500...599:
            return "OpenAI service is temporarily unavailable (HTTP \(status)). Try again shortly."
        default:
            return "OpenAI TTS error (HTTP \(status)): \(body.prefix(200))"
        }
    }

    private func buildRequest(text: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            throw TTSError(message: "Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "input": text,
            "voice": voice,
            "response_format": "pcm",
            "speed": Double(speed),
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
