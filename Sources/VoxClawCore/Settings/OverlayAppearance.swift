import SwiftUI

/// A Codable color representation bridging to SwiftUI `Color`.
public struct CodableColor: Codable, Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public init(_ color: Color, opacity: Double = 1.0) {
        #if os(macOS)
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        self.red = Double(nsColor.redComponent)
        self.green = Double(nsColor.greenComponent)
        self.blue = Double(nsColor.blueComponent)
        #else
        let resolved = color.resolve(in: EnvironmentValues())
        self.red = Double(resolved.red)
        self.green = Double(resolved.green)
        self.blue = Double(resolved.blue)
        #endif
        self.opacity = opacity
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue).opacity(opacity)
    }

    public static let white = CodableColor(red: 1, green: 1, blue: 1)
    public static let black = CodableColor(red: 0, green: 0, blue: 0)
    public static let yellow = CodableColor(red: 1, green: 1, blue: 0)
}

/// All visual properties for the floating teleprompter overlay.
public struct OverlayAppearance: Codable, Sendable, Equatable {
    public var fontFamily: String = "Helvetica Neue"
    public var fontSize: CGFloat = 28
    public var fontWeight: String = "medium"
    public var lineHeightMultiplier: CGFloat = 1.2
    public var wordSpacing: CGFloat = 2
    public var textColor: CodableColor = .white
    public var highlightColor: CodableColor = CodableColor(red: 1, green: 1, blue: 0, opacity: 0.35)
    public var pastWordOpacity: Double = 0.5
    public var futureWordOpacity: Double = 0.9
    public var codeWordColor: CodableColor = CodableColor(red: 0.68, green: 0.68, blue: 0.90, opacity: 1.0)
    public var backgroundColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0, opacity: 0.85)
    public var cornerRadius: CGFloat = 20
    public var horizontalPadding: CGFloat = 20
    public var verticalPadding: CGFloat = 16
    public var panelWidthFraction: Double = 1.0 / 3.0
    public var panelHeight: CGFloat = 162

    /// Line spacing in points, derived from the multiplier and current font size.
    public var effectiveLineSpacing: CGFloat {
        fontSize * (lineHeightMultiplier - 1)
    }

    public init() {}

    // Explicit CodingKeys so we can decode legacy "lineSpacing" from old persisted data.
    private enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, fontWeight, lineHeightMultiplier, wordSpacing
        case textColor, highlightColor, pastWordOpacity, futureWordOpacity, codeWordColor
        case backgroundColor, cornerRadius, horizontalPadding, verticalPadding
        case panelWidthFraction, panelHeight
        // Legacy key — only used for decoding old data.
        case lineSpacing
    }

    public init(from decoder: Decoder) throws {
        let defaults = OverlayAppearance()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? defaults.fontFamily
        fontSize = try container.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? defaults.fontSize
        fontWeight = try container.decodeIfPresent(String.self, forKey: .fontWeight) ?? defaults.fontWeight
        // Prefer new multiplier; fall back to converting old point-based lineSpacing.
        if let multiplier = try container.decodeIfPresent(CGFloat.self, forKey: .lineHeightMultiplier) {
            lineHeightMultiplier = multiplier
        } else if let oldSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .lineSpacing) {
            lineHeightMultiplier = fontSize > 0 ? (oldSpacing / fontSize) + 1 : defaults.lineHeightMultiplier
        } else {
            lineHeightMultiplier = defaults.lineHeightMultiplier
        }
        wordSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .wordSpacing) ?? defaults.wordSpacing
        textColor = try container.decodeIfPresent(CodableColor.self, forKey: .textColor) ?? defaults.textColor
        highlightColor = try container.decodeIfPresent(CodableColor.self, forKey: .highlightColor) ?? defaults.highlightColor
        pastWordOpacity = try container.decodeIfPresent(Double.self, forKey: .pastWordOpacity) ?? defaults.pastWordOpacity
        futureWordOpacity = try container.decodeIfPresent(Double.self, forKey: .futureWordOpacity) ?? defaults.futureWordOpacity
        codeWordColor = try container.decodeIfPresent(CodableColor.self, forKey: .codeWordColor) ?? defaults.codeWordColor
        backgroundColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor) ?? defaults.backgroundColor
        cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? defaults.cornerRadius
        horizontalPadding = try container.decodeIfPresent(CGFloat.self, forKey: .horizontalPadding) ?? defaults.horizontalPadding
        verticalPadding = try container.decodeIfPresent(CGFloat.self, forKey: .verticalPadding) ?? defaults.verticalPadding
        panelWidthFraction = try container.decodeIfPresent(Double.self, forKey: .panelWidthFraction) ?? defaults.panelWidthFraction
        panelHeight = try container.decodeIfPresent(CGFloat.self, forKey: .panelHeight) ?? defaults.panelHeight
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontWeight, forKey: .fontWeight)
        try container.encode(lineHeightMultiplier, forKey: .lineHeightMultiplier)
        try container.encode(wordSpacing, forKey: .wordSpacing)
        try container.encode(textColor, forKey: .textColor)
        try container.encode(highlightColor, forKey: .highlightColor)
        try container.encode(pastWordOpacity, forKey: .pastWordOpacity)
        try container.encode(futureWordOpacity, forKey: .futureWordOpacity)
        try container.encode(codeWordColor, forKey: .codeWordColor)
        try container.encode(backgroundColor, forKey: .backgroundColor)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(horizontalPadding, forKey: .horizontalPadding)
        try container.encode(verticalPadding, forKey: .verticalPadding)
        try container.encode(panelWidthFraction, forKey: .panelWidthFraction)
        try container.encode(panelHeight, forKey: .panelHeight)
    }

    public var fontWeightValue: Font.Weight {
        switch fontWeight {
        case "ultraLight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return .medium
        }
    }

    public static func resetToDefaults() -> OverlayAppearance {
        OverlayAppearance()
    }
}
