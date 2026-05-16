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
    @Argument var displayID: CGDirectDisplayID
    @Flag(name: .long, help: "Persist across reboots. Default is for the current login session only.")
    var persistent: Bool = false

    func run() throws {
      let active = try Video.listActiveDisplays()
      let currentlyEnabled = active.contains(displayID)
      try applyState(id: displayID, enabled: !currentlyEnabled, persistent: persistent)
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
    let preDevices = Swift.Set(Audio.listOutputDevices())
    let preDefault = Audio.defaultOutputDevice()

    try Video.setEnabled(id: id, enabled: true, persistent: persistent)

    let defaultWasBuiltIn = preDefault.map { Audio.transportType($0) == kAudioDeviceTransportTypeBuiltIn } ?? false
    guard defaultWasBuiltIn else { return }

    if let newDevice = Audio.waitForNewOutputDevice(excluding: preDevices, timeout: 2.0) {
      try Audio.setDefaultOutputDevice(newDevice)
    }
  }

  private static func disableWithAudio(id: CGDirectDisplayID, persistent: Bool) throws {
    let preDefault = Audio.defaultOutputDevice()

    try Video.setEnabled(id: id, enabled: false, persistent: persistent)

    Thread.sleep(forTimeInterval: 0.3)

    guard let preDefault else { return }
    let stillPresent = Audio.listOutputDevices().contains(preDefault)
    guard !stillPresent else { return }

    if let builtIn = Audio.builtInOutputDevice() {
      try Audio.setDefaultOutputDevice(builtIn)
    }
  }
}
