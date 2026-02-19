import ArgumentParser
import Foundation
import os

struct CLIParser: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "milo",
        abstract: "Read text aloud with a teleprompter overlay",
        discussion: """
        EXAMPLES:
          milo "Hello, world!"              Read text aloud with teleprompter
          milo -a "Hello, world!"           Audio only (no overlay)
          milo --clipboard                  Read from clipboard
          milo --file article.txt           Read from file
          echo "Hello" | milo               Read from stdin
          milo --listen                     Start HTTP listener on port 4140
          milo --status                     Check if listener is running
          milo --send "Hello from CLI"      Send text to a running listener

        KEYBOARD CONTROLS (during playback):
          Space       Pause / Resume
          Escape      Stop
          ←           Skip back 3s
          →           Skip forward 3s

        NETWORK API (when --listen is active):
          POST /read  Send text (JSON {"text":"..."} or plain body)
          GET /status Health check

        LOGGING:
          Use --verbose to echo debug info to stderr.
          Structured logs via os.Logger (subsystem: com.malpern.himilo):
            log stream --predicate 'subsystem == "com.malpern.himilo"' --level debug
        """,
        version: "1.0.0 (1)"
    )

    @Flag(name: [.short, .customLong("audio-only")], help: "Play audio without showing the overlay")
    var audioOnly = false

    @Flag(name: [.short, .long], help: "Read text from clipboard")
    var clipboard = false

    @Option(name: [.short, .long], help: "Read text from a file")
    var file: String? = nil

    @Option(name: .long, help: "TTS voice (default: onyx)")
    var voice: String = "onyx"

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

        if listen {
            let listenPort = port
            Log.cli.info("Starting in listener mode on port \(listenPort, privacy: .public)")
            let cliContext = CLIContext(text: nil, audioOnly: audioOnly, voice: voice, listen: true, port: port, verbose: verbose)
            CLIContext.shared = cliContext
            MainActor.assumeIsolated {
                HiMiloApp.main()
            }
            return
        }

        let resolvedText = try InputResolver.resolve(
            positional: text,
            clipboardFlag: clipboard,
            filePath: file
        )

        guard !resolvedText.isEmpty else {
            throw ValidationError("No text provided. Use arguments, --clipboard, --file, or pipe via stdin.")
        }

        let selectedVoice = voice
        Log.cli.info("Reading \(resolvedText.count, privacy: .public) chars, voice=\(selectedVoice, privacy: .public)")
        let cliContext = CLIContext(text: resolvedText, audioOnly: audioOnly, voice: voice, verbose: verbose)
        CLIContext.shared = cliContext
        MainActor.assumeIsolated {
            HiMiloApp.main()
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
        let box = ResultBox()

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                box.value = "Error: \(error.localizedDescription)"
                return
            }
            guard let http = response as? HTTPURLResponse else {
                box.value = "Error: invalid response"
                return
            }
            if let data, let body = String(data: data, encoding: .utf8) {
                box.value = "[\(http.statusCode)] \(body)"
            } else {
                box.value = "[\(http.statusCode)] (no body)"
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return box.value ?? "Error: request timed out"
    }
}

private final class ResultBox: @unchecked Sendable {
    var value: String?
}

final class CLIContext: Sendable {
    nonisolated(unsafe) static var shared: CLIContext?

    let text: String?
    let audioOnly: Bool
    let voice: String
    let listen: Bool
    let port: UInt16
    let verbose: Bool

    init(text: String?, audioOnly: Bool, voice: String, listen: Bool = false, port: UInt16 = 4140, verbose: Bool = false) {
        self.text = text
        self.audioOnly = audioOnly
        self.voice = voice
        self.listen = listen
        self.port = port
        self.verbose = verbose
    }
}
