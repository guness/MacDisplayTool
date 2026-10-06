import CoreAudio
import CoreGraphics
import Foundation

public struct DisplayFailure: Error, LocalizedError, CustomStringConvertible {
  public let description: String
  public var errorDescription: String? { description }
  public init(_ description: String) { self.description = description }
}

public enum DisplayController {
  private static var preferences: UserDefaults { UserDefaults(suiteName: "com.guness.MacDisplayTool.shared")! }
  public static var lastDisabledDisplayID: CGDirectDisplayID? {
    let saved = preferences.object(forKey: "lastDisabledDisplayID") as? Int
      ?? UserDefaults.standard.object(forKey: "lastDisabledDisplayID") as? Int
    return saved.flatMap(CGDirectDisplayID.init(exactly:))
  }

  public static func toggle(id: CGDirectDisplayID? = nil, persistent: Bool = false) throws {
    let active = try Video.listActiveDisplays()
    if let id {
      try applyState(id: id, enabled: !active.contains(id), persistent: persistent)
      if active.contains(id) { preferences.set(Int(id), forKey: "lastDisabledDisplayID") }
      return
    }
    if let target = active.first(where: { CGDisplayIsBuiltin($0) == 0 && !Video.isManagedVirtualDisplay($0) }) {
      try applyState(id: target, enabled: false, persistent: persistent)
      preferences.set(Int(target), forKey: "lastDisabledDisplayID")
      return
    }
    var candidates: [CGDirectDisplayID] = []
    if let saved = lastDisabledDisplayID, !Video.isManagedVirtualDisplay(saved) { candidates.append(saved) }
    for id: CGDirectDisplayID in [2, 3, 4, 5] where !candidates.contains(id) && !Video.isManagedVirtualDisplay(id) { candidates.append(id) }
    var lastError: Error?
    for id in candidates {
      do {
        try applyState(id: id, enabled: true, persistent: persistent)
        preferences.set(Int(id), forKey: "lastDisabledDisplayID")
        return
      } catch { lastError = error }
    }
    throw lastError ?? Video.Error.displayNotActive(id: 0)
  }

  public static func applyState(id: CGDirectDisplayID, enabled: Bool, persistent: Bool) throws {
    guard !Video.isManagedVirtualDisplay(id) else {
      throw DisplayFailure("Display \(id) is a managed virtual display. Use the profile menu or DisplayTool profile off instead of a physical-display toggle.")
    }
    let previous = Audio.defaultOutputDevice()
    let displayOutput = Audio.studioDisplayOutputDevice()
    try Video.setEnabled(id: id, enabled: enabled, persistent: persistent)
    if enabled {
      guard previous.map({ Audio.transportType($0) == kAudioDeviceTransportTypeBuiltIn }) ?? false else { return }
      if let output = Audio.studioDisplayOutputDevice() { try Audio.setDefaultOutputDevice(output) }
    } else if let previous, previous == displayOutput, let builtIn = Audio.builtInOutputDevice() {
      try Audio.setDefaultOutputDevice(builtIn)
    }
  }
}
