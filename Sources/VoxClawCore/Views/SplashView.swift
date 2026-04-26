#if os(macOS)
import SwiftUI

struct SplashView: View {
    private var appIcon: NSImage? {
        NSApp.applicationIconImage
            ?? NSImage(named: "AppIcon")
            ?? (Bundle.main.image(forResource: "AppIcon") as NSImage?)
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 128, height: 128)
            }

            Text("VoxClaw")
                .font(.system(size: 28, weight: .bold))

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(40)
        .frame(width: 280, height: 260)
    }
}
#endif
