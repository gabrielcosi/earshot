import AppKit
import CoreAudio

/// An app, or a process no app launched, that plays sound on this Mac.
public struct AudioSource: Identifiable, Hashable, Sendable {
    /// Stays the same when the app restarts its audio helpers: the owning app's bundle
    /// identifier, or for a process no app launched, its own bundle identifier and name.
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The processes Core Audio knows, grouped by the app they play for. Only what macOS registers
/// as a running app is a source: system daemons that keep an output open (speech, alerts) and
/// command-line tools have no app name and are not offered.
///
/// Apps rarely play from their own process: Chromium and Electron apps play from a helper the
/// app launched, so a helper is grouped under the first regular app up its parent chain. WebKit
/// apps play from a media process launchd starts, one per app, and macOS offers no public way to
/// ask which app that is (the system's "responsibility" tracking is private). WebKit names the
/// process after its app ("Safari Graphics and Media"), so it goes to the running app whose whole
/// name starts its name; with none, it stands for itself.
public enum AudioSources {
    /// What is known about one process, for grouping it.
    struct ProcessDetails {
        let bundleID: String?
        let name: String?
        /// A regular app: one with a Dock icon and a menu bar.
        let isApp: Bool
        let parent: pid_t
    }

    /// Sources playing sound right now, by name.
    public static func playing() -> [AudioSource] {
        let apps = runningApps()
        let sources = processObjects().filter { isPlaying($0) }.compactMap { object in
            pid(of: object).flatMap { source(of: $0, apps: apps, lookup: info(of:)) }
        }
        return Array(Set(sources)).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Every process object, playing or not, that belongs to one of `ids`.
    public static func processObjects(for ids: Set<String>) -> [AudioObjectID] {
        let apps = runningApps()
        return processObjects().filter { object in
            guard let pid = pid(of: object),
                let source = source(of: pid, apps: apps, lookup: info(of:))
            else { return false }
            return ids.contains(source.id)
        }
    }

    /// The source `pid` plays for; nil for Earshot and the processes it launched. `apps` are the
    /// running regular apps, for naming a process no app launched.
    static func source(
        of pid: pid_t, apps: [AudioSource], lookup: (pid_t) -> ProcessDetails?
    ) -> AudioSource? {
        let own = getpid()
        var current = pid
        while current > 1, current != own, let info = lookup(current) {
            if info.isApp, let id = info.bundleID {
                return AudioSource(id: id, name: info.name ?? id)
            }
            current = info.parent
        }
        guard current != own, let info = lookup(pid), let name = info.name else { return nil }
        let namedAfter = apps.filter { name.hasPrefix($0.name + " ") }
            .max { $0.name.count < $1.name.count }
        return namedAfter ?? AudioSource(id: "\(info.bundleID ?? "")/\(name)", name: name)
    }

    private static func runningApps() -> [AudioSource] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                let name = app.localizedName
            else { return nil }
            return AudioSource(id: id, name: name)
        }
    }

    private static func info(of pid: pid_t) -> ProcessDetails? {
        let app = NSRunningApplication(processIdentifier: pid)
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let parent = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size ? bsd.pbi_ppid : 0
        guard app != nil || parent != 0 else { return nil }
        return ProcessDetails(
            bundleID: app?.bundleIdentifier, name: app?.localizedName,
            isApp: app?.activationPolicy == .regular, parent: pid_t(parent))
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            return []
        }
        var objects = [AudioObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr
        else { return [] }
        return objects
    }

    private static func pid(of object: AudioObjectID) -> pid_t? {
        value(of: object, kAudioProcessPropertyPID, pid_t(-1)).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func isPlaying(_ object: AudioObjectID) -> Bool {
        value(of: object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) == 1
    }

    private static func value<Value>(
        of object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: Value
    ) -> Value? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            guard let base = bytes.baseAddress else { return kAudioHardwareBadPropertySizeError }
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, base)
        }
        return status == noErr ? value : nil
    }
}
