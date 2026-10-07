import ArgumentParser
import DisplayCore
import Foundation

extension DisplayTool {
  struct OpenApp: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "app", abstract: "Open the menu bar app.")
    func run() throws { try MenuAppClient.open(); print("MacDisplayTool menu bar app opened.") }
  }

  struct Profile: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Manage saved resolutions and activate them in the menu bar app.",
      subcommands: [Add.self, List.self, Remove.self, Activate.self, Status.self, Off.self])

    struct Add: ParsableCommand {
      @Argument var name: String
      @Argument var width: Int
      @Argument var height: Int
      @Option(name: .long) var refreshRate: Double = 60
      func run() throws {
        let profile = ResolutionProfile(name: name, width: width, height: height, refreshRate: refreshRate)
        try ProfileStore().update { try $0.upsert(profile) }
        print("Saved \(profile.name): \(profile.detail)")
      }
    }
    struct List: ParsableCommand {
      func run() throws {
        let document = try ProfileStore().read()
        if document.profiles.isEmpty { print("No profiles. Use DisplayTool profile add <name> <width> <height>.") }
        for profile in document.profiles { print("\(profile.name): \(profile.detail)") }
      }
    }
    struct Remove: ParsableCommand {
      @Argument var name: String
      func run() throws {
        try ProfileStore().update { document in try document.remove(id: document.profile(named: name).id) }
        print("Removed \(name).")
      }
    }
    struct Activate: ParsableCommand {
      @Argument var name: String
      func run() throws {
        if name.caseInsensitiveCompare("Default") == .orderedSame {
          _ = try MenuAppClient.request(.init(action: .off))
          print("Active: Default (system resolution).")
          return
        }
        let profile = try ProfileStore().read().profile(named: name)
        let response = try MenuAppClient.request(.init(action: .activate, profileID: profile.id))
        print("Active: \(profile.name), \(profile.detail), display \(response.status.displayID ?? 0). You can close this terminal.")
      }
    }
    struct Status: ParsableCommand {
      func run() throws {
        let response = try MenuAppClient.request(.init(action: .status))
        if response.status.sessionActive == false { print("Resolution profiles are paused: this is not the Mac's active login session.") }
        else if let profile = response.status.profile { print("Active: \(profile.name), \(profile.detail), display \(response.status.displayID ?? 0).") }
        else { print("Active: Default (system resolution).") }
        if let error = response.status.error { print("Last error: \(error)") }
      }
    }
    struct Off: ParsableCommand {
      func run() throws { _ = try MenuAppClient.request(.init(action: .off)); print("Virtual display off.") }
    }
  }
}

enum MenuAppClient {
  static func applicationURL() throws -> URL {
    let manager = FileManager.default
    var candidates: [URL] = []
    if let override = ProcessInfo.processInfo.environment["MACDISPLAYTOOL_APP"] { candidates.append(URL(fileURLWithPath: override)) }
    if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
      var ancestor = executable.deletingLastPathComponent()
      for _ in 0..<7 {
        if ancestor.pathExtension == "app" { candidates.append(ancestor) }
        candidates.append(ancestor.appendingPathComponent("dist/MacDisplayTool.app"))
        ancestor.deleteLastPathComponent()
      }
    }
    candidates += [URL(fileURLWithPath: "/Applications/MacDisplayTool.app"), manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/MacDisplayTool.app")]
    guard let url = candidates.first(where: { manager.fileExists(atPath: $0.appendingPathComponent("Contents/MacOS/DisplayMenu").path) }) else {
      throw DisplayFailure("Menu bar app not found. Build it with scripts/build-app.sh or install MacDisplayTool.app in Applications.")
    }
    return url
  }

  static func open(url: URL? = nil) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-g", "-a", try applicationURL().path] + (url.map { [$0.absoluteString] } ?? [])
    let pipe = Pipe(); process.standardError = pipe
    try process.run()
    let error = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw DisplayFailure("Cannot open the menu bar app: \(error)") }
  }

  static func request(_ request: AppRequest) throws -> AppResponse {
    let store = ProfileStore()
    try FileManager.default.createDirectory(at: store.requestsDirectory, withIntermediateDirectories: true)
    let responseURL = store.requestsDirectory.appendingPathComponent("\(request.requestID.uuidString).json")
    defer { try? FileManager.default.removeItem(at: responseURL) }
    try open(url: request.url)
    for _ in 0..<150 {
      if FileManager.default.fileExists(atPath: responseURL.path) {
        let response = try JSONDecoder().decode(AppResponse.self, from: Data(contentsOf: responseURL))
        if let error = response.error { throw DisplayFailure(error) }
        return response
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    throw DisplayFailure("The menu bar app did not respond. A graphical login session is required.")
  }
}
