import AppIntents
import os

/// App Intent that lets Shortcuts and Siri send text to HiMilo.
///
/// Usage from Shortcuts app: search for "Read Text Aloud" and select HiMilo.
/// Usage from CLI: `shortcuts run "Read with HiMilo"`
struct ReadTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Text Aloud"
    static let description: IntentDescription = IntentDescription(
        "Reads the provided text aloud using HiMilo's text-to-speech.",
        categoryName: "Reading"
    )

    @Parameter(title: "Text to Read")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Read \(\.$text) aloud")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Log.app.info("Received text via App Intent (\(text.count) chars)")
        await SharedApp.coordinator.readText(
            text,
            appState: SharedApp.appState,
            settings: SharedApp.settings
        )
        return .result()
    }
}

/// Registers discoverable shortcuts for Siri and Spotlight.
struct HiMiloShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReadTextIntent(),
            phrases: [
                "Read with \(.applicationName)",
                "Read text using \(.applicationName)",
            ],
            shortTitle: "Read Text",
            systemImageName: "waveform"
        )
    }
}
