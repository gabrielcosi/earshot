import CoreAudio
import Foundation

/// Audio input devices, as Core Audio lists them.
public enum AudioDevices {
    public struct Input: Identifiable, Hashable, Sendable {
        public let uid: String
        public let name: String
        public var id: String { uid }
    }

    public static func inputs() -> [Input] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let devices: [AudioObjectID] = array(system, kAudioHardwarePropertyDevices)
        return devices.compactMap { device in
            let streams: [AudioStreamID] = array(
                device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            guard !streams.isEmpty, let uid = string(device, kAudioDevicePropertyDeviceUID),
                let name = string(device, kAudioObjectPropertyName)
            else { return nil }
            return Input(uid: uid, name: name)
        }
    }

    public static func device(uid: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func array<Element>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [Element] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        let count = Int(size) / MemoryLayout<Element>.stride
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<Element>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else {
            return []
        }
        return Array(
            UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: Element.self), count: count))
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector)
        -> String?
    {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
            let value
        else { return nil }
        return value.takeRetainedValue() as String
    }
}
