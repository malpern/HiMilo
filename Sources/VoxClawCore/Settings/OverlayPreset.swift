import Foundation

/// A named, hand-tuned overlay style that users can apply with one click.
public struct OverlayPreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let appearance: OverlayAppearance

    /// All built-in style presets, ordered for gallery display.
    public static let all: [OverlayPreset] = [
        // MARK: - Legibility-focused

        OverlayPreset(
            id: "classic",
            name: "Classic",
            appearance: OverlayAppearance()  // Default values
        ),

        OverlayPreset(
            id: "highContrast",
            name: "High Contrast",
            appearance: {
                var a = OverlayAppearance()
                a.fontFamily = "SF Pro"
                a.fontSize = 32
                a.fontWeight = "bold"
                a.textColor = .white
                a.highlightColor = CodableColor(red: 0, green: 1, blue: 1, opacity: 0.4)
                a.backgroundColor = CodableColor(red: 0, green: 0, blue: 0, opacity: 0.95)
                return a
            }()
        ),

        OverlayPreset(
            id: "paper",
            name: "Paper",
            appearance: {
                var a = OverlayAppearance()
                a.fontFamily = "Georgia"
                a.fontSize = 26
                a.fontWeight = "regular"
                a.textColor = CodableColor(red: 0.25, green: 0.18, blue: 0.12)
                a.highlightColor = CodableColor(red: 0.9, green: 0.55, blue: 0.2, opacity: 0.3)
                a.backgroundColor = CodableColor(red: 0.98, green: 0.95, blue: 0.88, opacity: 0.92)
                return a
            }()
        ),

        OverlayPreset(
            id: "nightReader",
            name: "Night Reader",
            appearance: {
                var a = OverlayAppearance()
                a.fontFamily = "Avenir"
                a.fontSize = 28
                a.fontWeight = "regular"
                a.textColor = CodableColor(red: 1.0, green: 0.8, blue: 0.4)
                a.highlightColor = CodableColor(red: 1.0, green: 0.6, blue: 0.3, opacity: 0.3)
                a.backgroundColor = CodableColor(red: 0.05, green: 0.05, blue: 0.15, opacity: 0.9)
                return a
            }()
        ),

        OverlayPreset(
            id: "ocean",
            name: "Ocean",
            appearance: {
                var a = OverlayAppearance()
                a.fontFamily = "Helvetica Neue"
                a.fontSize = 28
                a.fontWeight = "medium"
                a.textColor = .white
                a.highlightColor = CodableColor(red: 0.0, green: 0.9, blue: 0.85, opacity: 0.35)
                a.backgroundColor = CodableColor(red: 0.0, green: 0.2, blue: 0.3, opacity: 0.88)
                return a
            }()
        ),

        OverlayPreset(
            id: "focus",
            name: "Focus",
            appearance: {
                var a = OverlayAppearance()
                a.fontFamily = "SF Pro"
                a.fontSize = 34
                a.fontWeight = "semibold"
                a.textColor = .white
                a.highlightColor = CodableColor(red: 1, green: 1, blue: 1, opacity: 0.25)
                a.backgroundColor = CodableColor(red: 0, green: 0, blue: 0, opacity: 0.92)
                return a
            }()
        ),

        // MARK: - Unique / Stylish

        OverlayPreset(
            id: "terminal",
            name: "Terminal",
            appearance: {
                var a = OverlayAppearance()
                a.fontFamily = "SF Mono"
                a.fontSize = 28
                a.fontWeight = "medium"
                a.textColor = CodableColor(red: 0.0, green: 1.0, blue: 0.0)
                a.highlightColor = CodableColor(red: 0.0, green: 0.8, blue: 0.0, opacity: 0.3)
                a.backgroundColor = CodableColor(red: 0, green: 0, blue: 0, opacity: 0.95)
                return a
            }()
        ),

        OverlayPreset(
            id: "sunset",
            name: "Sunset",
            appearance: {
                var a = OverlayAppearance()
                a.fontFamily = "Futura"
                a.fontSize = 28
                a.fontWeight = "medium"
                a.textColor = CodableColor(red: 1.0, green: 0.5, blue: 0.35)
                a.highlightColor = CodableColor(red: 1.0, green: 0.4, blue: 0.6, opacity: 0.35)
                a.backgroundColor = CodableColor(red: 0.2, green: 0.05, blue: 0.25, opacity: 0.88)
                return a
            }()
        ),

        OverlayPreset(
            id: "typewriter",
            name: "Typewriter",
            appearance: {
                var a = OverlayAppearance()
                a.fontFamily = "Menlo"
                a.fontSize = 24
                a.fontWeight = "regular"
                a.textColor = CodableColor(red: 0.25, green: 0.25, blue: 0.25)
                a.highlightColor = CodableColor(red: 1.0, green: 1.0, blue: 0.0, opacity: 0.25)
                a.backgroundColor = CodableColor(red: 0.95, green: 0.92, blue: 0.82, opacity: 0.9)
                return a
            }()
        ),

        OverlayPreset(
            id: "noir",
            name: "Noir",
            appearance: {
                var a = OverlayAppearance()
                a.fontFamily = "Helvetica Neue"
                a.fontSize = 28
                a.fontWeight = "light"
                a.textColor = CodableColor(red: 0.78, green: 0.78, blue: 0.78)
                a.highlightColor = CodableColor(red: 1, green: 1, blue: 1, opacity: 0.2)
                a.backgroundColor = CodableColor(red: 0.2, green: 0.2, blue: 0.2, opacity: 0.9)
                return a
            }()
        ),
    ]
}
