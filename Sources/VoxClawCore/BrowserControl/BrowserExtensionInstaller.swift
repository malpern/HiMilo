import Foundation

#if os(macOS)
import AppKit

enum BrowserExtensionInstallStatus: Equatable {
    case installed
    case missingAssets
    case missingHostManifest
}

struct BrowserExtensionInstaller {
    private let fileManager = FileManager.default

    func installBundledSupport(appBundleURL: URL = Bundle.main.bundleURL) throws {
        let resourcesURL = appBundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let bundledExtensionURL = resourcesURL.appendingPathComponent("ChromeExtension", isDirectory: true)

        guard fileManager.fileExists(atPath: bundledExtensionURL.path) else {
            throw NSError(domain: "BrowserExtensionInstaller", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Bundled Chrome extension assets were not found."
            ])
        }

        try fileManager.createDirectory(at: BrowserControlRuntime.appSupportDirectory, withIntermediateDirectories: true)
        try replaceItem(at: BrowserControlRuntime.extensionInstallDirectory, with: bundledExtensionURL)
        try writeNativeHostScript(appBundleURL: appBundleURL)
        try writeNativeHostManifest(
            to: chromeNativeMessagingHostDirectory(browserFolder: "Google/Chrome"),
            description: "VoxClaw browser control host for Google Chrome"
        )
        try writeNativeHostManifest(
            to: chromeNativeMessagingHostDirectory(browserFolder: "Google/Chrome Canary"),
            description: "VoxClaw browser control host for Google Chrome Canary"
        )
    }

    func installStatus() -> BrowserExtensionInstallStatus {
        guard fileManager.fileExists(atPath: BrowserControlRuntime.extensionInstallDirectory.path) else {
            return .missingAssets
        }
        let chromeManifest = chromeNativeMessagingHostDirectory(browserFolder: "Google/Chrome")
            .appendingPathComponent("\(BrowserControlRuntime.nativeHostName).json")
        let canaryManifest = chromeNativeMessagingHostDirectory(browserFolder: "Google/Chrome Canary")
            .appendingPathComponent("\(BrowserControlRuntime.nativeHostName).json")
        guard fileManager.fileExists(atPath: chromeManifest.path) || fileManager.fileExists(atPath: canaryManifest.path) else {
            return .missingHostManifest
        }
        return .installed
    }

    func extensionFolderURL() -> URL {
        BrowserControlRuntime.extensionInstallDirectory
    }

    func openChromeExtensionsPage() {
        guard let url = URL(string: "chrome://extensions") else { return }
        NSWorkspace.shared.open(url)
    }

    func openChromeCanaryExtensionsPage() {
        guard let url = URL(string: "chrome://extensions"),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome.canary") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func writeNativeHostScript(appBundleURL: URL) throws {
        let binaryURL = appBundleURL.appendingPathComponent("Contents/MacOS/VoxClaw")
        let script = """
        #!/bin/sh
        exec "\(binaryURL.path)" --browser-control-native-host 2>>/tmp/voxclaw-native-host.log
        """
        try script.write(to: BrowserControlRuntime.nativeHostScriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: BrowserControlRuntime.nativeHostScriptURL.path)
    }

    private func writeNativeHostManifest(to directory: URL, description: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifestURL = directory.appendingPathComponent("\(BrowserControlRuntime.nativeHostName).json")
        let manifest: [String: Any] = [
            "name": BrowserControlRuntime.nativeHostName,
            "description": description,
            "path": BrowserControlRuntime.nativeHostScriptURL.path,
            "type": "stdio",
            "allowed_origins": [
                "chrome-extension://\(BrowserControlRuntime.extensionID)/"
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestURL)
    }

    private func replaceItem(at destinationURL: URL, with sourceURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func chromeNativeMessagingHostDirectory(browserFolder: String) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(browserFolder, isDirectory: true)
            .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
    }
}
#endif
