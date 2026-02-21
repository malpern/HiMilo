import ArgumentParser
import Foundation
import Synchronization
import os

struct CLIParser: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "voxclaw",
        abstract: "Read text aloud with a teleprompter overlay",
        discussion: """
        EXAMPLES:
          voxclaw "Hello, world!"              Read text aloud with teleprompter
          voxclaw -a "Hello, world!"           Audio only (no overlay)
          voxclaw --clipboard                  Read from clipboard
          voxclaw --file article.txt           Read from file
          echo "Hello" | voxclaw               Read from stdin
          voxclaw --listen                     Start HTTP listener on port 4140
          voxclaw --status                     Check if listener is running
          voxclaw --send "Hello from CLI"      Send text to a running listener

        INTEGRATION (send text to the running menu bar app):
          URL Scheme:
            open "voxclaw://read?text=Hello%20world"
          Services Menu:
            Select text in any app > right-click > Services > Read with VoxClaw
          Shortcuts / Siri:
            Search for "Read Text Aloud" in the Shortcuts app
            shortcuts run "Read with VoxClaw"

        NETWORK API (when --listen is active):
          POST /read  Send text (JSON {"text":"..."} or plain body)
          GET /status Health check

        LOGGING:
          Use --verbose to echo debug info to stderr.
          Structured logs via os.Logger (subsystem: com.malpern.voxclaw):
            log stream --predicate 'subsystem == "com.malpern.voxclaw"' --level debug
        """,
        version: "1.0.1 (2)"
    )

    @Flag(name: [.short, .customLong("audio-only")], help: "Play audio without showing the overlay")
    var audioOnly = false

    @Flag(name: [.short, .long], help: "Read text from clipboard")
    var clipboard = false

    @Option(name: [.short, .long], help: "Read text from a file")
    var file: String? = nil

    @Option(name: .long, help: "TTS voice (default: onyx)")
    var voice: String = "onyx"

    @Option(name: .long, help: "Speech speed multiplier, 0.25–4.0 (default: 1.0)")
    var rate: Float = 1.0

    @Option(name: .long, help: "Save audio to file instead of playing (OpenAI only, saves as MP3)")
    var output: String? = nil

    @Flag(name: [.short, .long], help: "Start network listener for LAN text input")
    var listen = false

    @Option(name: .long, help: "Network listener port (default: 4140)")
    var port: UInt16 = 4140

    @Flag(name: [.short, .customLong("verbose")], help: "Print debug info to stderr")
    var verbose = false

    @Flag(name: .long, help: "Query a running listener's status")
    var status = false

    @Option(name: .long, help: "Send text to a running listener")
    var send: String? = nil

    @Argument(help: "Text to read aloud")
    var text: [String] = []

    mutating func run() throws {
        if verbose {
            Log.isVerbose = true
            Log.verbose("Verbose mode enabled")
        }

        // --status: query a running listener
        if status {
            queryStatus()
            return
        }

        // --send: send text to a running listener
        if let sendText = send {
            sendToListener(sendText)
            return
        }

        let resolvedText = try InputResolver.resolve(
            positional: text,
            clipboardFlag: clipboard,
            filePath: file
        )

        // --output: save audio to file without launching the app
        if let outputPath = output {
            guard !resolvedText.isEmpty else {
                throw ValidationError("No text provided. Use arguments, --clipboard, --file, or pipe via stdin.")
            }
            saveAudioToFile(resolvedText, outputPath: outputPath)
            return
        }

        if listen {
            let listenPort = port
            Log.cli.info("Starting in listener mode on port \(listenPort, privacy: .public)")
            let cliContext = CLIContext(text: nil, audioOnly: audioOnly, voice: voice, rate: rate, listen: true, port: port, verbose: verbose)
            MainActor.assumeIsolated {
                CLIContext.shared = cliContext
                VoxClawApp.main()
            }
            return
        }

        guard !resolvedText.isEmpty else {
            throw ValidationError("No text provided. Use arguments, --clipboard, --file, or pipe via stdin.")
        }

        let selectedVoice = voice
        Log.cli.info("Reading \(resolvedText.count, privacy: .public) chars, voice=\(selectedVoice, privacy: .public)")
        let cliContext = CLIContext(text: resolvedText, audioOnly: audioOnly, voice: voice, rate: rate, verbose: verbose)
        MainActor.assumeIsolated {
            CLIContext.shared = cliContext
            VoxClawApp.main()
        }
    }

    // MARK: - Output to File

    private func saveAudioToFile(_ text: String, outputPath: String) {
        guard let apiKey = try? KeychainHelper.readAPIKey() else {
            print("Error: --output requires an OpenAI API key.")
            print("  Run: security add-generic-password -a openai -s openai-voice-api-key -w sk-...")
            Foundation.exit(1)
        }

        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": voice,
            "response_format": "mp3",
            "speed": Double(rate),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Launch the network request on a background queue so URLSession can also
        // dispatch TLS/reachability work back to the main RunLoop without deadlocking.
        let semaphore = DispatchSemaphore(value: 0)
        let capturedRequest = request
        DispatchQueue.global(qos: .userInitiated).async {
            let task = URLSession(configuration: .ephemeral).dataTask(with: capturedRequest) { data, response, error in
                defer { semaphore.signal() }
                if let error {
                    print("Error: \(error.localizedDescription)")
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    print("Error: API returned HTTP \(code)")
                    return
                }
                let dest: URL
                if outputPath.hasPrefix("/") || outputPath.hasPrefix("~") {
                    dest = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
                } else {
                    dest = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        .appendingPathComponent(outputPath)
                }
                do {
                    try data.write(to: dest)
                    print("Saved \(data.count / 1024) KB to \(dest.path)")
                } catch {
                    print("Error saving file: \(error)")
                }
            }
            task.resume()
        }
        // Keep the main RunLoop alive so CFNetwork can deliver any main-thread callbacks.
        let deadline = Date(timeIntervalSinceNow: 60)
        while semaphore.wait(timeout: .now()) == .timedOut && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    // MARK: - Remote Commands

    private func queryStatus() {
        let url = URL(string: "http://localhost:\(port)/status")!
        let result = Self.syncHTTP(URLRequest(url: url))
        print(result)
    }

    private func sendToListener(_ text: String) {
        let url = URL(string: "http://localhost:\(port)/read")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        let result = Self.syncHTTP(request)
        print(result)
    }

    private static func syncHTTP(_ request: URLRequest) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        let result = Mutex<String?>(nil)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result.withLock { $0 = "Error: \(error.localizedDescription)" }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                result.withLock { $0 = "Error: invalid response" }
                return
            }
            if let data, let body = String(data: data, encoding: .utf8) {
                result.withLock { $0 = "[\(http.statusCode)] \(body)" }
            } else {
                result.withLock { $0 = "[\(http.statusCode)] (no body)" }
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return result.withLock { $0 } ?? "Error: request timed out"
    }
}

final class CLIContext: Sendable {
    @MainActor static var shared: CLIContext?

    let text: String?
    let audioOnly: Bool
    let voice: String
    let rate: Float
    let listen: Bool
    let port: UInt16
    let verbose: Bool

    init(text: String?, audioOnly: Bool, voice: String, rate: Float = 1.0, listen: Bool = false, port: UInt16 = 4140, verbose: Bool = false) {
        self.text = text
        self.audioOnly = audioOnly
        self.voice = voice
        self.rate = rate
        self.listen = listen
        self.port = port
        self.verbose = verbose
    }
}
