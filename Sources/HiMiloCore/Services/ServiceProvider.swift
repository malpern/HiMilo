import AppKit
import os

/// Provides macOS Services menu integration.
/// Users can select text in any app, right-click > Services > "Read with HiMilo".
@MainActor
final class HiMiloServiceProvider: NSObject {
    private let onReadText: (String) async -> Void

    init(onReadText: @escaping (String) async -> Void) {
        self.onReadText = onReadText
        super.init()
    }

    /// Called by the Services menu. Selector must match NSMessage in Info.plist.
    @objc func readText(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text was provided." as NSString
            return
        }

        Log.app.info("Received text via Services menu (\(text.count) chars)")
        Task { @MainActor in
            await onReadText(text)
        }
    }
}
