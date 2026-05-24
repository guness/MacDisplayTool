import ArgumentParser
import CoreAudio
import CoreGraphics
import Foundation

@main
struct DisplayTool: ParsableCommand {
  static let configuration: CommandConfiguration = .init(subcommands: [List.self, Set.self, Toggle.self])
}

extension DisplayTool {
  struct List: ParsableCommand {
    func run() throws {
      let ids = try Video.listActiveDisplays()
      print("Active Display IDs:\n\(ids.map(String.init).joined(separator: ", "))")
    }
  }

  struct Set: ParsableCommand {
    @Argument var displayID: CGDirectDisplayID
    @Flag var configuration: Configuration
    @Flag(name: .long, help: "Persist across reboots. Default is for the current login session only.")
    var persistent: Bool = false

    func run() throws {
      try applyState(id: displayID, enabled: configuration != .disabled, persistent: persistent)
    }

    enum Configuration: String, EnumerableFlag {
      case enabled
      case disabled
    }
  }

  struct Toggle: ParsableCommand {
    static let lastDisabledKey = "lastDisabledDisplayID"
    static let enableFallbackIDs: [CGDirectDisplayID] = [2, 3, 4, 5]

    @Argument(help: "Display ID to toggle. Omit to auto-pick the first non-built-in display (or restore the last disabled one).")
    var displayID: CGDirectDisplayID?
    @Flag(name: .long, help: "Persist across reboots. Default is for the current login session only.")
    var persistent: Bool = false

    func run() throws {
      if let id = displayID {
        let active = try Video.listActiveDisplays()
        let currentlyEnabled = active.contains(id)
        try applyState(id: id, enabled: !currentlyEnabled, persistent: persistent)
        return
      }

      let externals = try Video.listActiveDisplays().filter { CGDisplayIsBuiltin($0) == 0 }
      if let target = externals.first {
        try applyState(id: target, enabled: false, persistent: persistent)
        UserDefaults.standard.set(Int(target), forKey: Self.lastDisabledKey)
        return
      }

      var candidates: [CGDirectDisplayID] = []
      let saved = UserDefaults.standard.object(forKey: Self.lastDisabledKey) as? Int
      if let saved { candidates.append(CGDirectDisplayID(saved)) }
      for id in Self.enableFallbackIDs where !candidates.contains(id) {
        candidates.append(id)
      }

      var lastError: Swift.Error?
      for id in candidates {
        do {
          try applyState(id: id, enabled: true, persistent: persistent)
          UserDefaults.standard.set(Int(id), forKey: Self.lastDisabledKey)
          return
        } catch {
          lastError = error
        }
      }
      throw lastError ?? Video.Error.displayNotActive(id: 0)
    }
  }

  static func applyState(id: CGDirectDisplayID, enabled: Bool, persistent: Bool) throws {
    if enabled {
      try enableWithAudio(id: id, persistent: persistent)
    } else {
      try disableWithAudio(id: id, persistent: persistent)
    }
  }

  private static func enableWithAudio(id: CGDirectDisplayID, persistent: Bool) throws {
    let preDefault = Audio.defaultOutputDevice()

    try Video.setEnabled(id: id, enabled: true, persistent: persistent)

    let defaultIsBuiltIn = preDefault.map { Audio.transportType($0) == kAudioDeviceTransportTypeBuiltIn } ?? false
    guard defaultIsBuiltIn else { return }

    if let displayOutput = Audio.studioDisplayOutputDevice() {
      try Audio.setDefaultOutputDevice(displayOutput)
    }
  }

  private static func disableWithAudio(id: CGDirectDisplayID, persistent: Bool) throws {
    let preDefault = Audio.defaultOutputDevice()
    let displayOutput = Audio.studioDisplayOutputDevice()

    try Video.setEnabled(id: id, enabled: false, persistent: persistent)

    guard let preDefault, preDefault == displayOutput else { return }
    if let builtIn = Audio.builtInOutputDevice() {
      try Audio.setDefaultOutputDevice(builtIn)
    }
  }
}
