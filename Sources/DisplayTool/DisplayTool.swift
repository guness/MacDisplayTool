import ArgumentParser
import CoreAudio
import CoreGraphics
import Foundation

@main
struct DisplayTool: ParsableCommand {
  static let configuration: CommandConfiguration = .init(subcommands: [List.self, Set.self])
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
      let enabled = configuration != .disabled
      if enabled {
        try enableWithAudio()
      } else {
        try disableWithAudio()
      }
    }

    private func enableWithAudio() throws {
      let preDevices = Swift.Set(Audio.listOutputDevices())
      let preDefault = Audio.defaultOutputDevice()

      try Video.setEnabled(id: displayID, enabled: true, persistent: persistent)

      let defaultWasBuiltIn = preDefault.map { Audio.transportType($0) == kAudioDeviceTransportTypeBuiltIn } ?? false
      guard defaultWasBuiltIn else { return }

      if let newDevice = Audio.waitForNewOutputDevice(excluding: preDevices, timeout: 2.0) {
        try Audio.setDefaultOutputDevice(newDevice)
      }
    }

    private func disableWithAudio() throws {
      let preDefault = Audio.defaultOutputDevice()

      try Video.setEnabled(id: displayID, enabled: false, persistent: persistent)

      Thread.sleep(forTimeInterval: 0.3)

      guard let preDefault else { return }
      let stillPresent = Audio.listOutputDevices().contains(preDefault)
      guard !stillPresent else { return }

      if let builtIn = Audio.builtInOutputDevice() {
        try Audio.setDefaultOutputDevice(builtIn)
      }
    }

    enum Configuration: String, EnumerableFlag {
      case enabled
      case disabled
    }
  }
}
