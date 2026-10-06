import ArgumentParser
import DisplayCore
import CoreGraphics
import Foundation

@main
struct DisplayTool: ParsableCommand {
  static let configuration: CommandConfiguration = .init(subcommands: [List.self, Set.self, Toggle.self, Virtual.self, VirtualStop.self, Profile.self, OpenApp.self])
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
    @Argument(help: "Display ID to toggle. Omit to auto-pick a physical external display (or restore the last disabled one).")
    var displayID: CGDirectDisplayID?
    @Flag(name: .long, help: "Persist across reboots. Default is for the current login session only.")
    var persistent: Bool = false

    func run() throws {
      try DisplayController.toggle(id: displayID, persistent: persistent)
    }
  }

  static func applyState(id: CGDirectDisplayID, enabled: Bool, persistent: Bool) throws {
    try DisplayController.applyState(id: id, enabled: enabled, persistent: persistent)
  }
}
