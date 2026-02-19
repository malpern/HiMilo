import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsManager
    @State private var isTestingVoice = false

    var body: some View {
        Form {
            Section("Voice Engine") {
                Picker("Engine", selection: $settings.voiceEngine) {
                    Text("Apple (Built-in)").tag(VoiceEngineType.apple)
                    Text("OpenAI (Higher Quality)").tag(VoiceEngineType.openai)
                }
                .pickerStyle(.radioGroup)

                if settings.voiceEngine == .apple {
                    Text("Uses your Mac's built-in text-to-speech. No account required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Uses OpenAI's neural voices for natural-sounding speech. Requires your own OpenAI API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.voiceEngine == .apple {
                Section("Apple Voice") {
                    Picker("Voice", selection: appleVoiceBinding) {
                        Text("System Default").tag("" as String)
                        ForEach(availableAppleVoices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))")
                                .tag(voice.identifier)
                        }
                    }
                }
            }

            if settings.voiceEngine == .openai {
                Section("OpenAI Account") {
                    SecureField("API Key", text: $settings.openAIAPIKey)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        if !settings.isOpenAIConfigured {
                            Text("Paste your API key from OpenAI's dashboard.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Key saved", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Link("Get API Key",
                             destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.caption)
                    }

                    Picker("Voice", selection: $settings.openAIVoice) {
                        ForEach(openAIVoices, id: \.self) { voice in
                            Text(voice.capitalized).tag(voice)
                        }
                    }
                }

                Section {
                    Text("When using OpenAI voices, your text is sent to OpenAI's servers for processing. OpenAI's [privacy policy](https://openai.com/privacy) applies. No personal data beyond the reading text is shared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Playback") {
                Toggle("Audio Only (no teleprompter overlay)", isOn: $settings.audioOnly)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
    }

    private var appleVoiceBinding: Binding<String> {
        Binding(
            get: { settings.appleVoiceIdentifier ?? "" },
            set: { settings.appleVoiceIdentifier = $0.isEmpty ? nil : $0 }
        )
    }

    private var availableAppleVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }

    private let openAIVoices = ["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]
}
