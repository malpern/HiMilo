#if os(macOS)
import SwiftUI

struct AboutView: View {
    private var appIcon: NSImage? {
        NSApp.applicationIconImage
            ?? NSImage(named: "AppIcon")
            ?? (Bundle.main.image(forResource: "AppIcon") as NSImage?)
    }

    var body: some View {
        VStack(spacing: 16) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }

            Text("VoxClaw")
                .font(.title)
                .fontWeight(.bold)

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Give your agent a voice.")
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 40)

            Text("Created by Micah Alpern")
                .font(.callout)

            HStack(spacing: 20) {
                Link("Website", destination: URL(string: "https://voxclaw.com/")!)
                    .accessibilityIdentifier(AccessibilityID.About.websiteLink)
                Link("GitHub", destination: URL(string: "https://github.com/malpern/VoxClaw")!)
                    .accessibilityIdentifier(AccessibilityID.About.githubLink)
                Link("Twitter", destination: URL(string: "https://www.x.com/malpern")!)
                    .accessibilityIdentifier(AccessibilityID.About.twitterLink)
            }
            .font(.callout)
        }
        .padding(32)
        .frame(width: 320)
    }
}
#endif
