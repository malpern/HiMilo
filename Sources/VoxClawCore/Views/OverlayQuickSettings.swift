import SwiftUI

struct OverlayQuickSettings: View {
    @Bindable var settings: SettingsManager
    @State private var showCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Settings")
                .font(.headline)

            OverlayPresetGallery(settings: settings, compact: true)

            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCustom.toggle()
                    }
                } label: {
                    Text("Custom")
                        .font(.caption)
                        .underline()
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.QuickSettings.customToggle)
            }

            if showCustom {
                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Font Size: \(Int(settings.overlayAppearance.fontSize))pt")
                            .font(.caption)
                        Slider(value: fontSizeBinding, in: 16...64, step: 1)
                            .accessibilityIdentifier(AccessibilityID.QuickSettings.fontSizeSlider)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Background Opacity: \(Int(settings.overlayAppearance.backgroundColor.opacity * 100))%")
                            .font(.caption)
                        Slider(value: bgOpacityBinding, in: 0.1...1.0, step: 0.05)
                            .accessibilityIdentifier(AccessibilityID.QuickSettings.bgOpacitySlider)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Line Spacing: \(Int(settings.overlayAppearance.lineSpacing))pt")
                            .font(.caption)
                        Slider(value: lineSpacingBinding, in: 0...20, step: 1)
                            .accessibilityIdentifier(AccessibilityID.QuickSettings.lineSpacingSlider)
                    }

                    ColorPicker("Text Color", selection: textColorBinding)
                        .font(.caption)
                        .accessibilityIdentifier(AccessibilityID.QuickSettings.textColorPicker)

                    ColorPicker("Highlight Color", selection: highlightColorBinding)
                        .font(.caption)
                        .accessibilityIdentifier(AccessibilityID.QuickSettings.highlightColorPicker)
                }

                Divider()

                Button("Reset to Defaults") {
                    settings.overlayAppearance = .resetToDefaults()
                }
                .font(.caption)
                .accessibilityIdentifier(AccessibilityID.QuickSettings.resetButton)
            }
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Bindings

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.overlayAppearance.fontSize) },
            set: { settings.overlayAppearance.fontSize = CGFloat($0) }
        )
    }

    private var bgOpacityBinding: Binding<Double> {
        Binding(
            get: { settings.overlayAppearance.backgroundColor.opacity },
            set: { settings.overlayAppearance.backgroundColor.opacity = $0 }
        )
    }

    private var lineSpacingBinding: Binding<Double> {
        Binding(
            get: { Double(settings.overlayAppearance.lineSpacing) },
            set: { settings.overlayAppearance.lineSpacing = CGFloat($0) }
        )
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { Color(red: settings.overlayAppearance.textColor.red,
                         green: settings.overlayAppearance.textColor.green,
                         blue: settings.overlayAppearance.textColor.blue) },
            set: { newColor in
                let nsColor = NSColor(newColor).usingColorSpace(.sRGB) ?? NSColor(newColor)
                settings.overlayAppearance.textColor = CodableColor(
                    red: Double(nsColor.redComponent),
                    green: Double(nsColor.greenComponent),
                    blue: Double(nsColor.blueComponent),
                    opacity: settings.overlayAppearance.textColor.opacity
                )
            }
        )
    }

    private var highlightColorBinding: Binding<Color> {
        Binding(
            get: { Color(red: settings.overlayAppearance.highlightColor.red,
                         green: settings.overlayAppearance.highlightColor.green,
                         blue: settings.overlayAppearance.highlightColor.blue) },
            set: { newColor in
                let nsColor = NSColor(newColor).usingColorSpace(.sRGB) ?? NSColor(newColor)
                settings.overlayAppearance.highlightColor = CodableColor(
                    red: Double(nsColor.redComponent),
                    green: Double(nsColor.greenComponent),
                    blue: Double(nsColor.blueComponent),
                    opacity: settings.overlayAppearance.highlightColor.opacity
                )
            }
        )
    }
}
