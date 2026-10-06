import CoreGraphics
import Darwin
import Foundation

public enum VirtualAgent {
  public static let label = "com.guness.MacDisplayTool.virtual"
  static var domain: String { "gui/\(getuid())" }
  static var service: String { "\(domain)/\(label)" }
  public static var plistURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(label).plist")
  }
  static var logURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/MacDisplayTool/virtual.log")
  }

  public static func configuration(executable: String, logPath: String, width: Int, height: Int,
                            refreshRate: Double, name: String) -> [String: Any] {
    [
      "Label": label,
      "ProgramArguments": [executable, "virtual", String(width), String(height),
                           "--refresh-rate", String(refreshRate), "--name", name],
      "RunAtLoad": true,
      "KeepAlive": true,
      "LimitLoadToSessionType": "Aqua",
      "ThrottleInterval": 10,
      "StandardOutPath": logPath,
      "StandardErrorPath": logPath
    ]
  }

  public static func install(width: Int, height: Int, refreshRate: Double, name: String) throws {
    guard getuid() != 0 else {
      throw DisplayFailure("Run persistent virtual displays as the logged-in user, without sudo.")
    }
    try requireSuccess(["print", domain], message: "A graphical login session is required. Log in to the Mac first.")
    guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
      throw DisplayFailure("Cannot locate the executable for login startup.")
    }
    let manager = FileManager.default
    try manager.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try manager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let previous = manager.fileExists(atPath: plistURL.path) ? try Data(contentsOf: plistURL) : nil
    let config = configuration(executable: executable.path, logPath: logURL.path,
                               width: width, height: height, refreshRate: refreshRate, name: name)
    let data = try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0)
    // Inspect before stopping so genuine permission failures do not get ignored.
    try stopIfLoaded()
    do {
      try data.write(to: plistURL, options: .atomic)
      try requireSuccess(["enable", service], message: "Cannot enable the virtual display agent.")
      try requireSuccess(["bootstrap", domain, plistURL.path], message: "Cannot start the virtual display agent.")
      // A successful bootstrap alone does not mean macOS accepted the display.
      for _ in 0..<100 {
        if try Video.listActiveDisplays().contains(where: {
          CGDisplayVendorNumber($0) == 0x4D44 && CGDisplayModelNumber($0) == 1
            && CGDisplayPixelsWide($0) == width && CGDisplayPixelsHigh($0) == height
        }) { return }
        Thread.sleep(forTimeInterval: 0.1)
      }
      throw DisplayFailure("The agent started but macOS did not create the requested display. See \(logURL.path).")
    } catch {
      // Restore an earlier persistent configuration if an update fails.
      try? stopIfLoaded()
      if let previous {
        try previous.write(to: plistURL, options: .atomic)
        try requireSuccess(["bootstrap", domain, plistURL.path], message: "Cannot restore the previous virtual display agent.")
      } else if manager.fileExists(atPath: plistURL.path) {
        try manager.removeItem(at: plistURL)
      }
      throw error
    }
  }

  public static func remove() throws {
    try stopIfLoaded()
    if FileManager.default.fileExists(atPath: plistURL.path) {
      try FileManager.default.removeItem(at: plistURL)
    }
  }

  private static func stopIfLoaded() throws {
    let result = try launchctl(["print", service])
    if result.status == 0 {
      try requireSuccess(["bootout", service], message: "Cannot stop the virtual display agent.")
    } else if result.status != 113 && result.status != 3 {
      throw DisplayFailure("Cannot inspect the virtual display agent: \(result.output)")
    }
  }

  private static func requireSuccess(_ arguments: [String], message: String) throws {
    let result = try launchctl(arguments)
    guard result.status == 0 else {
      throw DisplayFailure("\(message) \(result.output)")
    }
  }

  private static func launchctl(_ arguments: [String]) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    // Drain before waiting to avoid blocking on a full output pipe.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
