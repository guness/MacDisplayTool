import CoreAudio
import Foundation

enum Audio {
  enum Error: Swift.Error, CustomStringConvertible {
    case coreAudio(api: String, status: OSStatus)

    var description: String {
      switch self {
      case .coreAudio(let api, let status):
        return "\(api) failed with OSStatus \(status)."
      }
    }
  }

  private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

  // MARK: - Defaults

  static func defaultOutputDevice() -> AudioDeviceID? {
    readDefault(selector: kAudioHardwarePropertyDefaultOutputDevice)
  }

  /// Sets both the default output device and the default *system* output
  /// (alerts/UI sounds) to the given device.
  static func setDefaultOutputDevice(_ id: AudioDeviceID) throws {
    try writeDefault(selector: kAudioHardwarePropertyDefaultOutputDevice, id: id)
    try writeDefault(selector: kAudioHardwarePropertyDefaultSystemOutputDevice, id: id)
  }

  // MARK: - Enumeration

  static func listOutputDevices() -> [AudioDeviceID] {
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &devices) == noErr else { return [] }
    return devices.filter(hasOutputStreams)
  }

  static func builtInOutputDevice() -> AudioDeviceID? {
    listOutputDevices().first { transportType($0) == kAudioDeviceTransportTypeBuiltIn }
  }

  static func transportType(_ id: AudioDeviceID) -> UInt32? {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
    return value
  }

  // MARK: - Polling

  /// Polls until a new output device appears that isn't in `excluding`, or
  /// until `timeout` elapses. Returns the first new device found.
  static func waitForNewOutputDevice(excluding: Set<AudioDeviceID>, timeout: TimeInterval) -> AudioDeviceID? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if let new = listOutputDevices().first(where: { !excluding.contains($0) }) {
        return new
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return nil
  }

  // MARK: - Internals

  private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
  }

  private static func readDefault(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
    var addr = address(selector)
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &id)
    return status == noErr ? id : nil
  }

  private static func writeDefault(selector: AudioObjectPropertySelector, id: AudioDeviceID) throws {
    var addr = address(selector)
    var deviceID = id
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectSetPropertyData(systemObject, &addr, 0, nil, size, &deviceID)
    guard status == noErr else {
      throw Error.coreAudio(api: "AudioObjectSetPropertyData(\(selector))", status: status)
    }
  }

  private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
    return size > 0
  }
}
