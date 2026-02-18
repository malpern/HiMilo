import Foundation

actor TTSService {
    private let apiKey: String
    private let voice: String
    private let model = "gpt-4o-mini-tts"

    init(apiKey: String, voice: String = "onyx") {
        self.apiKey = apiKey
        self.voice = voice
    }

    struct TTSError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    func streamPCM(text: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(text: text)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw TTSError(message: "Invalid response type")
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await byte in bytes {
                            errorBody.append(Character(UnicodeScalar(byte)))
                        }
                        throw TTSError(message: "TTS API error (\(httpResponse.statusCode)): \(errorBody)")
                    }

                    // Stream in chunks of 4800 bytes (~100ms of 24kHz 16-bit mono)
                    let chunkSize = 4800
                    var buffer = Data()

                    for try await byte in bytes {
                        buffer.append(byte)
                        if buffer.count >= chunkSize {
                            let chunk = buffer.prefix(chunkSize)
                            continuation.yield(Data(chunk))
                            buffer = Data(buffer.dropFirst(chunkSize))
                        }
                    }

                    // Yield remaining bytes
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
