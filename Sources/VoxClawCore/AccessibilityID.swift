/// Stable accessibility identifiers for all interactive UI elements.
/// Used by macOS accessibility APIs (e.g. Peekaboo, XCUITest, AppleScript).
enum AccessibilityID {
    enum MenuBar {
        static let pauseResume = "menuBar.pauseResume"
        static let stop = "menuBar.stop"
        static let readClipboard = "menuBar.readClipboard"
        static let readFromFile = "menuBar.readFromFile"
        static let settings = "menuBar.settings"
        static let about = "menuBar.about"
        static let quit = "menuBar.quit"
    }

    enum Overlay {
        static let panel = "overlay.panel"
        static let settingsButton = "overlay.settingsButton"
        static let pauseButton = "overlay.pauseButton"
        static let feedbackBadge = "overlay.feedbackBadge"
    }

    enum Settings {
        static let copyAgentSetup = "settings.copyAgentSetup"
        static let showInstructions = "settings.showInstructions"
        static let voiceEnginePicker = "settings.voiceEnginePicker"
        static let appleVoicePicker = "settings.appleVoicePicker"
        static let openAIVoicePicker = "settings.openAIVoicePicker"
        static let apiKeyField = "settings.apiKeyField"
        static let pasteAPIKey = "settings.pasteAPIKey"
        static let getAPIKeyLink = "settings.getAPIKeyLink"
        static let readingStyleField = "settings.readingStyleField"
        static let removeAPIKey = "settings.removeAPIKey"
        static let networkListenerToggle = "settings.networkListenerToggle"
        static let pauseOtherAudioToggle = "settings.pauseOtherAudioToggle"
        static let audioOnlyToggle = "settings.audioOnlyToggle"
        static let launchAtLoginToggle = "settings.launchAtLoginToggle"
    }

    enum Appearance {
        static let fontPicker = "appearance.fontPicker"
        static let fontSizeSlider = "appearance.fontSizeSlider"
        static let fontWeightPicker = "appearance.fontWeightPicker"
        static let lineSpacingSlider = "appearance.lineSpacingSlider"
        static let wordSpacingSlider = "appearance.wordSpacingSlider"
        static let textColorPicker = "appearance.textColorPicker"
        static let highlightColorPicker = "appearance.highlightColorPicker"
        static let pastOpacitySlider = "appearance.pastOpacitySlider"
        static let futureOpacitySlider = "appearance.futureOpacitySlider"
        static let bgColorPicker = "appearance.bgColorPicker"
        static let bgOpacitySlider = "appearance.bgOpacitySlider"
        static let panelWidthSlider = "appearance.panelWidthSlider"
        static let panelHeightSlider = "appearance.panelHeightSlider"
        static let hPaddingSlider = "appearance.hPaddingSlider"
        static let vPaddingSlider = "appearance.vPaddingSlider"
        static let cornerRadiusSlider = "appearance.cornerRadiusSlider"
        static let resetButton = "appearance.resetButton"
    }

    enum QuickSettings {
        static let fontSizeSlider = "quickSettings.fontSizeSlider"
        static let bgOpacitySlider = "quickSettings.bgOpacitySlider"
        static let lineSpacingSlider = "quickSettings.lineSpacingSlider"
        static let textColorPicker = "quickSettings.textColorPicker"
        static let highlightColorPicker = "quickSettings.highlightColorPicker"
        static let resetButton = "quickSettings.resetButton"
        static let customToggle = "quickSettings.customToggle"
    }

    enum Onboarding {
        static let backButton = "onboarding.backButton"
        static let pauseButton = "onboarding.pauseButton"
        static let getStartedButton = "onboarding.getStartedButton"
        static let continueButton = "onboarding.continueButton"
        static let finishButton = "onboarding.finishButton"
        static let apiKeyField = "onboarding.apiKeyField"
        static let pasteAPIKey = "onboarding.pasteAPIKey"
        static let removeAPIKey = "onboarding.removeAPIKey"
        static let getAPIKeyLink = "onboarding.getAPIKeyLink"
        static let thisMacButton = "onboarding.thisMacButton"
        static let remoteMachineButton = "onboarding.remoteMachineButton"
        static let launchAtLoginToggle = "onboarding.launchAtLoginToggle"
        static let portField = "onboarding.portField"
        static let portOKButton = "onboarding.portOKButton"
        static let portCancelButton = "onboarding.portCancelButton"
    }

    enum PresetGallery {
        static func card(_ presetID: String) -> String {
            "presetGallery.\(presetID)"
        }
    }

    enum About {
        static let websiteLink = "about.websiteLink"
        static let githubLink = "about.githubLink"
        static let twitterLink = "about.twitterLink"
    }
}
