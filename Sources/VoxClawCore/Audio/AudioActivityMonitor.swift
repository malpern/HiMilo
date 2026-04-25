#if os(macOS)
import Foundation
import CoreAudio
import os

/// Detects whether any process from a configured "defer-list" is currently
/// producing audio output. Used by the speech queue to politely wait for
/// voice/video calls (Zoom, Teams, ChatGPT/Claude desktop, etc.) before speaking.
public enum AudioActivityMonitor {
    /// Bundle IDs whose audio output we wait for rather than talk over.
    public static let deferListBundleIDs: [String] = [
        "com.openai.chat",              // ChatGPT desktop
        "com.anthropic.claudefordesktop", // Claude desktop
        "us.zoom.xos",                  // Zoom
        "com.microsoft.teams2",         // Microsoft Teams
        "com.apple.FaceTime",           // FaceTime
        "com.hnc.Discord"               // Discord
    ]

    /// Returns the bundle IDs from the defer-list that are currently producing
    /// audio output. Empty array means it's safe to speak. Returns empty on any
    /// CoreAudio error so we fail open (speak normally).
    public static func activeDeferListBundleIDs(deferList: [String] = deferListBundleIDs) -> [String] {
        let audioProcessList: [AudioObjectID]
        do {
            audioProcessList = try fetchProcessObjectList()
        } catch {
            Log.audio.warning("AudioActivityMonitor: failed to fetch process list: \(error.localizedDescription, privacy: .public)")
            return []
        }

        let deferSet = Set(deferList)
        var active: [String] = []
        for processID in audioProcessList {
            guard let bundleID = bundleID(for: processID), deferSet.contains(bundleID) else { continue }
            if isRunningOutput(processID: processID) {
                active.append(bundleID)
            }
        }
        return active
    }

    public static func isAnyDeferListAppActive(deferList: [String] = deferListBundleIDs) -> Bool {
        !activeDeferListBundleIDs(deferList: deferList).isEmpty
    }

    /// True when any non-VoxClaw process is currently capturing audio input
    /// (microphone). Used to suppress audio playback while the user is dictating
    /// to a transcription tool (Aqua Voice, Superwhisper, etc.). Fails open
    /// (returns false) on any CoreAudio error.
    public static func isAnyProcessUsingMicrophone() -> Bool {
        let audioProcessList: [AudioObjectID]
        do {
            audioProcessList = try fetchProcessObjectList()
        } catch {
            Log.audio.warning("AudioActivityMonitor: mic check failed to fetch process list: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let ownBundleID = Bundle.main.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for processID in audioProcessList {
            // Skip our own process so VoxClaw never defers because of itself.
            if let pid = pid(for: processID), pid == ownPID { continue }
            if let bundleID = bundleID(for: processID), bundleID == ownBundleID { continue }
            if isRunningInput(processID: processID) {
                return true
            }
        }
        return false
    }

    // MARK: - CoreAudio plumbing

    private struct CoreAudioError: Error {
        let status: OSStatus
        let context: String
        var localizedDescription: String { "\(context) (status=\(status))" }
    }

    private static func fetchProcessObjectList() throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr else { throw CoreAudioError(status: status, context: "GetPropertyDataSize(ProcessObjectList)") }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var objects = [AudioObjectID](repeating: 0, count: count)
        status = objects.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                buffer.baseAddress!
            )
        }
        guard status == noErr else { throw CoreAudioError(status: status, context: "GetPropertyData(ProcessObjectList)") }
        return objects
    }

    private static func bundleID(for processID: AudioObjectID) -> String? {
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

    private static func isRunningOutput(processID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(processID, &address, 0, nil, &size, &running)
        guard status == noErr else { return false }
        return running != 0
    }

    private static func isRunningInput(processID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(processID, &address, 0, nil, &size, &running)
        guard status == noErr else { return false }
        return running != 0
    }

    private static func pid(for processID: AudioObjectID) -> pid_t? {
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
}
#endif
