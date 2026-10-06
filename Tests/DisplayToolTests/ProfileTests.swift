import DisplayCore
import Foundation
import Testing

struct ProfileTests {
  @Test func profileNamesAreUniqueAndLookupIgnoresCase() throws {
    var document = ProfileDocument()
    let profile = ResolutionProfile(name: "  Remote Ultrawide  ", width: 3440, height: 1440)
    try document.upsert(profile)
    #expect(try document.profile(named: "remote ultrawide").id == profile.id)
    #expect(throws: DisplayFailure.self) {
      try document.upsert(ResolutionProfile(name: "REMOTE ULTRAWIDE", width: 1920, height: 1080))
    }
    #expect(throws: DisplayFailure.self) {
      try document.upsert(ResolutionProfile(name: "Default", width: 1920, height: 1080))
    }
    document.activeProfileID = profile.id
    #expect(throws: DisplayFailure.self) { try document.remove(id: profile.id) }
  }

  @Test func storePreservesChangesFromSeparateWritersAndRollsBackFailedEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = ProfileStore(directory: directory)
    let second = ProfileStore(directory: directory)
    let a = ResolutionProfile(name: "Laptop", width: 1920, height: 1200)
    let b = ResolutionProfile(name: "Tablet", width: 2732, height: 2048)
    try first.update { try $0.upsert(a) }
    try second.update { try $0.upsert(b) }
    #expect(try first.read().profiles.count == 2)
    #expect(throws: DisplayFailure.self) {
      try second.update { document in
        document.profiles.removeAll()
        throw DisplayFailure("Aborted edit")
      }
    }
    #expect(try first.read().profiles.count == 2)
  }

  @Test func requestsRoundTripAndRejectMissingOrMalformedIdentifiers() throws {
    let request = AppRequest(action: .activate, profileID: UUID())
    let parsed = try AppRequest(url: request.url)
    #expect(parsed.profileID == request.profileID)
    #expect(parsed.requestID == request.requestID)
    #expect(throws: DisplayFailure.self) {
      try AppRequest(url: URL(string: "macdisplaytool://activate?request=../../oops")!)
    }
    #expect(throws: DisplayFailure.self) {
      try AppRequest(url: AppRequest(action: .activate).url)
    }
  }
}
