import DisplayCore
import AppKit
@testable import DisplayMenu
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct SessionTests {
  @MainActor private final class Screen: ManagedVirtualDisplay {
    let displayID: UInt32
    var invalidated = false
    init(id: UInt32) { displayID = id }
    func invalidate() { invalidated = true }
  }

  @MainActor private final class Harness {
    var active = true
    var ready = true
    var screens: [Screen] = []
    let store: ProfileStore
    let profile = ResolutionProfile(name: "Tablet", width: 2732, height: 2048)
    let alternate = ResolutionProfile(name: "Laptop", width: 1920, height: 1200)

    init() throws {
      store = ProfileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
      try store.update {
        try $0.upsert(profile)
        try $0.upsert(alternate)
        $0.activeProfileID = profile.id
      }
    }
    func model() -> MenuModel {
      MenuModel(store: store, legacyAgentURL: nil, sessionActivity: { self.active }, createDisplay: { _ in
        let screen = Screen(id: UInt32(self.screens.count + 10000))
        self.screens.append(screen)
        return screen
      }, displayReady: { _, _ in self.ready })
    }
    func cleanup() { try? FileManager.default.removeItem(at: store.directory) }
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<100 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Session transition did not finish within one second")
  }

  @Test func inactiveStartupKeepsSelectionWithoutCreatingDisplay() async throws {
    let h = try Harness()
    defer { h.cleanup() }
    h.active = false
    let model = h.model()
    defer { model.shutdown() }
    await model.start()
    #expect(h.screens.isEmpty)
    #expect(model.status.sessionActive == false)
    #expect(model.activeProfile == nil)
    #expect(try h.store.read().activeProfileID == h.profile.id)
    await #expect(throws: DisplayFailure.self) { try await model.activate(h.alternate.id) }
    #expect(h.screens.isEmpty)
    #expect(try h.store.read().activeProfileID == h.profile.id)
  }

  @Test func switchAwayReleasesDisplayAndReturnRestoresSelection() async throws {
    let h = try Harness()
    defer { h.cleanup() }
    let model = h.model()
    defer { model.shutdown() }
    await model.start()
    #expect(model.activeProfile == h.profile)
    let first = try #require(h.screens.first)
    h.active = false
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    #expect(first.invalidated)
    #expect(model.status.displayID == nil)
    #expect(try h.store.read().activeProfileID == h.profile.id)
    h.active = true
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    try await waitUntil { model.activeProfile == h.profile }
    #expect(h.screens.count == 2)
    #expect(h.screens.last?.invalidated == false)
    #expect(model.status.sessionActive == true)
  }

  @Test func sessionSwitchDuringActivationCannotCommitStaleProfile() async throws {
    let h = try Harness()
    defer { h.cleanup() }
    let model = h.model()
    defer { model.shutdown() }
    await model.start()
    h.ready = false
    let switching = Task { try await model.activate(h.alternate.id) }
    try await waitUntil { h.screens.count == 2 }
    let pending = try #require(h.screens.last)
    h.active = false
    model.refresh()
    #expect(h.screens.allSatisfy { $0.invalidated })
    // Return before the original polling task wakes up: its generation is stale.
    h.active = true
    h.ready = true
    model.refresh()
    await #expect(throws: DisplayFailure.self) { try await switching.value }
    #expect(pending.invalidated)
    try await waitUntil { model.activeProfile == h.profile }
    #expect(try h.store.read().activeProfileID == h.profile.id)
    #expect(model.activeProfile != h.alternate)
    #expect(h.screens.count == 3)
  }

  @Test func choosingDefaultWhilePausedPreventsRestoration() async throws {
    let h = try Harness()
    defer { h.cleanup() }
    let model = h.model()
    defer { model.shutdown() }
    await model.start()
    h.active = false
    model.refresh()
    try model.off()
    h.active = true
    model.refresh()
    // Give the restoration task time to read the saved Default selection.
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.activeProfile == nil)
    #expect(h.screens.count == 1)
    #expect(try h.store.read().activeProfileID == nil)
  }

  @Test func quittingDuringActivationCannotRestoreOrCommitAfterShutdown() async throws {
    let h = try Harness()
    defer { h.cleanup() }
    let model = h.model()
    await model.start()
    h.ready = false
    let switching = Task { try await model.activate(h.alternate.id) }
    try await waitUntil { h.screens.count == 2 }
    model.shutdown()
    await #expect(throws: DisplayFailure.self) { try await switching.value }
    #expect(h.screens.allSatisfy { $0.invalidated })
    #expect(try h.store.read().activeProfileID == h.profile.id)
    #expect(!FileManager.default.fileExists(atPath: h.store.statusURL.path))
  }
}
