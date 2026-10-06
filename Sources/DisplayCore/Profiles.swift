import Darwin
import Foundation

public struct ResolutionProfile: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var name: String
  public var width: Int
  public var height: Int
  public var refreshRate: Double
  public init(id: UUID = UUID(), name: String, width: Int, height: Int, refreshRate: Double = 60) {
    self.id = id; self.name = name; self.width = width; self.height = height; self.refreshRate = refreshRate
  }
  public var detail: String { "\(width) × \(height) · \(refreshRate.formatted()) Hz" }
  public func validate() throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DisplayFailure("Enter a profile name.") }
    guard (1...16384).contains(width), (1...16384).contains(height) else {
      throw DisplayFailure("Width and height must be between 1 and 16384 pixels.")
    }
    guard refreshRate.isFinite, (1...240).contains(refreshRate) else { throw DisplayFailure("Refresh rate must be between 1 and 240 Hz.") }
  }
}

public struct ProfileDocument: Codable, Sendable {
  public var profiles: [ResolutionProfile] = []
  public var activeProfileID: UUID?
  public init() {}
  public func profile(named name: String) throws -> ResolutionProfile {
    guard let profile = profiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.id.uuidString.caseInsensitiveCompare(name) == .orderedSame }) else {
      throw DisplayFailure("Profile '\(name)' does not exist. Use DisplayTool profile list.")
    }
    return profile
  }
  public mutating func upsert(_ profile: ResolutionProfile) throws {
    try profile.validate()
    var cleaned = profile
    cleaned.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleaned.name.caseInsensitiveCompare("Default") != .orderedSame else {
      throw DisplayFailure("Default is reserved for the system resolution. Choose another profile name.")
    }
    guard !profiles.contains(where: { $0.id != cleaned.id && $0.name.caseInsensitiveCompare(cleaned.name) == .orderedSame }) else {
      throw DisplayFailure("A profile with this name already exists.")
    }
    if let index = profiles.firstIndex(where: { $0.id == cleaned.id }) { profiles[index] = cleaned }
    else { profiles.append(cleaned) }
  }
  public mutating func remove(id: UUID) throws {
    guard activeProfileID != id else { throw DisplayFailure("Select Default before deleting the active profile.") }
    profiles.removeAll { $0.id == id }
  }
}

public struct ProfileStore: Sendable {
  public let directory: URL
  public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacDisplayTool")) {
    self.directory = directory
  }
  public var documentURL: URL { directory.appendingPathComponent("profiles.json") }
  public var statusURL: URL { directory.appendingPathComponent("status.json") }
  public var requestsDirectory: URL { directory.appendingPathComponent("responses") }

  public func read() throws -> ProfileDocument {
    guard FileManager.default.fileExists(atPath: documentURL.path) else { return ProfileDocument() }
    return try JSONDecoder().decode(ProfileDocument.self, from: Data(contentsOf: documentURL))
  }
  @discardableResult
  public func update(_ edit: (inout ProfileDocument) throws -> Void) throws -> ProfileDocument {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fd = open(directory.appendingPathComponent("profiles.lock").path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw DisplayFailure("Cannot open the profile lock.") }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw DisplayFailure("Cannot lock the profile list.") }
    defer { flock(fd, LOCK_UN) }
    var document = try read()
    try edit(&document)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(document).write(to: documentURL, options: .atomic)
    return document
  }
}

public struct AppStatus: Codable, Sendable {
  public var processID: Int32
  public var profile: ResolutionProfile?
  public var displayID: UInt32?
  public var error: String?
  public init(profile: ResolutionProfile?, displayID: UInt32?, error: String? = nil) {
    processID = getpid(); self.profile = profile; self.displayID = displayID; self.error = error
  }
}

public struct AppResponse: Codable, Sendable {
  public var status: AppStatus
  public var error: String?
  public init(status: AppStatus, error: String? = nil) { self.status = status; self.error = error }
}

public struct AppRequest: Sendable {
  public enum Action: String, Sendable { case activate, off, status }
  public let action: Action
  public let profileID: UUID?
  public let requestID: UUID
  public init(action: Action, profileID: UUID? = nil, requestID: UUID = UUID()) {
    self.action = action; self.profileID = profileID; self.requestID = requestID
  }
  public var url: URL {
    var components = URLComponents()
    components.scheme = "macdisplaytool"; components.host = action.rawValue
    components.queryItems = [URLQueryItem(name: "request", value: requestID.uuidString)]
    if let profileID { components.queryItems?.append(URLQueryItem(name: "profile", value: profileID.uuidString)) }
    return components.url!
  }
  public init(url: URL) throws {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.scheme == "macdisplaytool",
          let host = components.host, let action = Action(rawValue: host),
          let value = components.queryItems?.first(where: { $0.name == "request" })?.value,
          let requestID = UUID(uuidString: value) else { throw DisplayFailure("Invalid app request.") }
    let profileID = components.queryItems?.first(where: { $0.name == "profile" })?.value.flatMap(UUID.init(uuidString:))
    guard action != .activate || profileID != nil else { throw DisplayFailure("Activation requires a profile ID.") }
    self.init(action: action, profileID: profileID, requestID: requestID)
  }
}
