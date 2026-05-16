import ArgumentParser
import CoreGraphics

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
      try Video.setEnabled(id: displayID, enabled: configuration != .disabled, persistent: persistent)
    }

    enum Configuration: String, EnumerableFlag {
      case enabled
      case disabled
    }
  }
}
