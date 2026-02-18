import ArgumentParser
import Foundation

struct CLIParser: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "milo",
        abstract: "Read text aloud with a teleprompter overlay"
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

    @Argument(help: "Text to read aloud")
    var text: [String] = []

    mutating func run() throws {
        if listen {
            let cliContext = CLIContext(text: nil, audioOnly: audioOnly, voice: voice, listen: true, port: port)
            CLIContext.shared = cliContext
            MainActor.assumeIsolated {
                HeyMiloApp.main()
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

        let cliContext = CLIContext(text: resolvedText, audioOnly: audioOnly, voice: voice)
        CLIContext.shared = cliContext
        MainActor.assumeIsolated {
            HeyMiloApp.main()
        }
    }
}

final class CLIContext: Sendable {
    nonisolated(unsafe) static var shared: CLIContext?

    let text: String?
    let audioOnly: Bool
    let voice: String
    let listen: Bool
    let port: UInt16

    init(text: String?, audioOnly: Bool, voice: String, listen: Bool = false, port: UInt16 = 4140) {
        self.text = text
        self.audioOnly = audioOnly
        self.voice = voice
        self.listen = listen
        self.port = port
    }
}
