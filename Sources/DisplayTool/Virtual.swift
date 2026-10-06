import ArgumentParser
import CoreGraphics
import Darwin
import Foundation
import VirtualDisplayBridge

extension DisplayTool {
  struct Virtual: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Create a custom-resolution virtual display for remote access until interrupted."
    )

    @Argument(help: "Pixel width (1–16384).") var width: Int
    @Argument(help: "Pixel height (1–16384).") var height: Int
    @Option(name: .long, help: "Refresh rate in Hz (1–240).") var refreshRate: Double = 60
    @Option(name: .long, help: "Display name shown in macOS.") var name: String = "MacDisplayTool Remote"

    func validate() throws {
      guard (1...16384).contains(width), (1...16384).contains(height) else {
        throw ValidationError("Width and height must each be between 1 and 16384 pixels; macOS may impose lower limits.")
      }
      guard refreshRate.isFinite, (1...240).contains(refreshRate) else {
        throw ValidationError("Refresh rate must be a finite value between 1 and 240 Hz.")
      }
      guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ValidationError("Display name must not be empty.")
      }
    }

    func run() throws {
      // Dispatch signal sources keep cleanup on the main queue, outside the signal handler.
      // Install them before creation: a client can observe the display immediately.
      signal(SIGINT, SIG_IGN)
      signal(SIGTERM, SIG_IGN)
      let sources = [SIGINT, SIGTERM].map { number in
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { Darwin.exit(0) }
        source.resume()
        return source
      }
      let display = try MDTVirtualDisplay.create(
        width: UInt(width), height: UInt(height), refreshRate: refreshRate, name: name
      )
      for source in sources {
        source.setEventHandler {
          display.invalidate()
          Darwin.exit(0)
        }
      }

      print("Virtual display \(display.displayID): \(width)×\(height) at \(refreshRate) Hz (\(name)).")
      print("Select this display in your remote client. Keep this command running; Ctrl-C removes it.")
      fflush(stdout)
      withExtendedLifetime((display, sources)) {
        RunLoop.main.run()
      }
    }
  }
}
