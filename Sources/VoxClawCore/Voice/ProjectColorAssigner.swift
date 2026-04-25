import Foundation
import CryptoKit
import SwiftUI

public struct ProjectIndicator: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let color: Color

    public init(projectId: String) {
        self.id = projectId
        self.name = ProjectColorAssigner.displayName(for: projectId)
        self.color = ProjectColorAssigner.color(for: projectId)
    }
}

/// Assigns a stable, deterministic color to a project_id by hashing the full
/// path into a curated palette. No persistence — the function is pure.
public enum ProjectColorAssigner {
    /// Twelve mid-saturation, panel-friendly hues chosen to stay visually
    /// distinct against a dark overlay. Order is intentional and the index
    /// produced by `color(for:)` is taken modulo this count.
    public static let palette: [Color] = [
        Color(hue: 0.00, saturation: 0.55, brightness: 0.85), // coral
        Color(hue: 0.07, saturation: 0.65, brightness: 0.90), // tangerine
        Color(hue: 0.13, saturation: 0.55, brightness: 0.90), // mustard
        Color(hue: 0.22, saturation: 0.50, brightness: 0.75), // olive
        Color(hue: 0.32, saturation: 0.50, brightness: 0.75), // sage
        Color(hue: 0.45, saturation: 0.55, brightness: 0.75), // teal
        Color(hue: 0.52, saturation: 0.55, brightness: 0.85), // cyan
        Color(hue: 0.58, saturation: 0.55, brightness: 0.90), // sky
        Color(hue: 0.65, saturation: 0.55, brightness: 0.85), // indigo
        Color(hue: 0.75, saturation: 0.50, brightness: 0.85), // violet
        Color(hue: 0.85, saturation: 0.55, brightness: 0.90), // magenta
        Color(hue: 0.95, saturation: 0.50, brightness: 0.90)  // rose
    ]

    /// Index into the palette for the given identifier. Stable and
    /// deterministic across runs and devices.
    public static func paletteIndex(for projectId: String) -> Int {
        let digest = SHA256.hash(data: Data(projectId.utf8))
        var slot: UInt64 = 0
        for (i, byte) in digest.prefix(8).enumerated() {
            slot |= UInt64(byte) << (8 * i)
        }
        return Int(slot % UInt64(palette.count))
    }

    public static func color(for projectId: String) -> Color {
        palette[paletteIndex(for: projectId)]
    }

    /// Display name from a project_id. Currently the basename of the path; if
    /// the id isn't path-shaped, returns it unchanged.
    public static func displayName(for projectId: String) -> String {
        let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        let component = (trimmed as NSString).lastPathComponent
        return component.isEmpty ? trimmed : component
    }
}
