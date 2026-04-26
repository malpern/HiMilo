#if os(macOS) && !APPSTORE
import Foundation
import CoreAudio
import os

/// Read-only probe over the CoreAudio process list. Abstracted so tests can
/// inject synthetic process tables without touching the system.
public protocol CoreAudioProbe: Sendable {
    func processObjects() -> [AudioObjectID]
    func bundleID(for processID: AudioObjectID) -> String?
    func pid(for processID: AudioObjectID) -> pid_t?
    func isRunningOutput(processID: AudioObjectID) -> Bool
    func isRunningInput(processID: AudioObjectID) -> Bool
}

/// Real probe backed by `kAudioHardwarePropertyProcessObjectList` and per-process
/// CoreAudio properties (macOS 14.4+). Returns empty / nil / false on any
/// CoreAudio error so callers fail open.
public struct SystemCoreAudioProbe: CoreAudioProbe {
    public init() {}

    public func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size
        )
        guard status == noErr else {
            Log.audio.warning("CoreAudioProbe: GetPropertyDataSize failed (status=\(status, privacy: .public))")
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var objects = [AudioObjectID](repeating: 0, count: count)
        status = objects.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return OSStatus(kAudioHardwareUnspecifiedError) }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address, 0, nil, &size, base
            )
        }
        guard status == noErr else {
            Log.audio.warning("CoreAudioProbe: GetPropertyData failed (status=\(status, privacy: .public))")
            return []
        }
        return objects
    }

    public func bundleID(for processID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var bundleRef: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &bundleRef) { ptr -> OSStatus in
            AudioObjectGetPropertyData(processID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let cfRef = bundleRef else { return nil }
        return cfRef.takeRetainedValue() as String
    }

    public func pid(for processID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(processID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    public func isRunningOutput(processID: AudioObjectID) -> Bool {
        runningProperty(processID: processID, selector: kAudioProcessPropertyIsRunningOutput)
    }

    public func isRunningInput(processID: AudioObjectID) -> Bool {
        runningProperty(processID: processID, selector: kAudioProcessPropertyIsRunningInput)
    }

    private func runningProperty(processID: AudioObjectID, selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(processID, &address, 0, nil, &size, &running)
        guard status == noErr else { return false }
        return running != 0
    }
}

/// Detects whether any process from a configured "defer-list" is currently
/// producing audio output, or any non-VoxClaw process is using the microphone.
/// Used by the speech queue to politely wait for voice/video calls (Zoom,
/// Teams, ChatGPT/Claude desktop, etc.) and dictation tools (Aqua Voice,
/// Superwhisper) before speaking.
public enum AudioActivityMonitor {
    /// Bundle IDs whose audio output we wait for rather than talk over.
    public static let deferListBundleIDs: [String] = [
        "com.openai.chat",                 // ChatGPT desktop
        "com.anthropic.claudefordesktop",  // Claude desktop
        "us.zoom.xos",                     // Zoom
        "com.microsoft.teams2",            // Microsoft Teams
        "com.apple.FaceTime",              // FaceTime
        "com.hnc.Discord"                  // Discord
    ]

    /// Returns the bundle IDs from the defer-list that are currently producing
    /// audio output. Empty array means it's safe to speak.
    public static func activeDeferListBundleIDs(
        deferList: [String] = deferListBundleIDs,
        probe: CoreAudioProbe = SystemCoreAudioProbe()
    ) -> [String] {
        let deferSet = Set(deferList)
        var active: [String] = []
        for processID in probe.processObjects() {
            guard let bundleID = probe.bundleID(for: processID), deferSet.contains(bundleID) else { continue }
            if probe.isRunningOutput(processID: processID) {
                active.append(bundleID)
            }
        }
        return active
    }

    /// True when any non-VoxClaw process is currently capturing audio input
    /// (microphone). VoxClaw's own process is excluded by both PID and bundle ID.
    public static func isAnyProcessUsingMicrophone(
        probe: CoreAudioProbe = SystemCoreAudioProbe(),
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        for processID in probe.processObjects() {
            if let pid = probe.pid(for: processID), pid == ownPID { continue }
            if let bundleID = probe.bundleID(for: processID), bundleID == ownBundleID { continue }
            if probe.isRunningInput(processID: processID) {
                return true
            }
        }
        return false
    }
}
#endif
