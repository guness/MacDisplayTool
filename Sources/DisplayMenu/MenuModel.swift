import AppKit
import CoreGraphics
import DisplayCore
import ServiceManagement
import SwiftUI
import VirtualDisplayBridge

struct PhysicalDisplay: Identifiable, Equatable {
  var id: CGDirectDisplayID
  var name: String
}

@MainActor
final class MenuModel: ObservableObject {
  @Published private(set) var document = ProfileDocument()
  @Published private(set) var activeProfile: ResolutionProfile?
  @Published private(set) var physicalDisplays: [PhysicalDisplay] = []
  @Published private(set) var lastDisabledID: CGDirectDisplayID?
  @Published private(set) var error: String?
  @Published private(set) var loginEnabled = false
  @Published private(set) var loginNeedsApproval = false
  @Published private(set) var isChanging = false
  @Published private(set) var isSessionActive: Bool
  @Published private(set) var defaultResolution = "System resolution"
  private let store: ProfileStore
  private let legacyAgentURL: URL?
  private let sessionActivity: @MainActor () -> Bool
  private let createDisplay: @MainActor (ResolutionProfile) throws -> any ManagedVirtualDisplay
  private let displayReady: @MainActor (UInt32, ResolutionProfile) -> Bool
  private var display: (any ManagedVirtualDisplay)?
  private var pendingDisplay: (any ManagedVirtualDisplay)?
  private var sessionGeneration: UInt64 = 0
  private var sessionObservers: [NSObjectProtocol] = []
  private var restoreTask: Task<Void, Never>?
  private var hasStarted = false
  private var isShuttingDown = false
  private var timer: Timer?
  private var profilesWindow: NSWindow?

  init(store: ProfileStore = ProfileStore(),
       legacyAgentURL: URL? = VirtualAgent.plistURL,
       sessionActivity: @escaping @MainActor () -> Bool = { LoginSession.isActive },
       createDisplay: @escaping @MainActor (ResolutionProfile) throws -> any ManagedVirtualDisplay = {
         try MDTVirtualDisplay.create(width: UInt($0.width), height: UInt($0.height),
                                      refreshRate: $0.refreshRate, name: $0.name)
       },
       displayReady: @escaping @MainActor (UInt32, ResolutionProfile) -> Bool = {
         CGDisplayIsActive($0) != 0 && CGDisplayPixelsWide($0) == $1.width && CGDisplayPixelsHigh($0) == $1.height
       }) {
    self.store = store
    self.legacyAgentURL = legacyAgentURL
    self.sessionActivity = sessionActivity
    self.createDisplay = createDisplay
    self.displayReady = displayReady
    isSessionActive = sessionActivity()
  }

  var status: AppStatus {
    AppStatus(profile: activeProfile, displayID: display?.displayID, error: error, sessionActive: isSessionActive)
  }

  private var sessionFailure: DisplayFailure {
    DisplayFailure("Resolution profiles are paused because this is not the Mac's active login session. Share the active desktop or switch to this user on the Mac, then try again.")
  }

  private func observeSessionChanges() {
    let center = NSWorkspace.shared.notificationCenter
    sessionObservers = [
      center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.updateSessionActivity(false) }
      },
      center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.updateSessionActivity(self.sessionActivity())
        }
      }
    ]
  }

  private func updateSessionActivity(_ active: Bool) {
    guard !isShuttingDown, active != isSessionActive else { return }
    isSessionActive = active
    sessionGeneration &+= 1
    restoreTask?.cancel()
    if !active {
      // Keep the selection on disk, but relinquish both current and in-flight screens.
      display?.invalidate(); display = nil
      pendingDisplay?.invalidate(); pendingDisplay = nil
      activeProfile = nil
      error = nil
      publishStatus()
    } else if hasStarted {
      let generation = sessionGeneration
      restoreTask = Task { [weak self] in
        guard let self else { return }
        do {
          // An interrupted activation must finish cleaning up before restoring.
          while self.isChanging { try await Task.sleep(for: .milliseconds(50)) }
          try Task.checkCancellation()
          guard self.isSessionActive, self.sessionGeneration == generation else { return }
          self.document = try self.store.read()
          if let id = self.document.activeProfileID { try await self.activate(id) }
          self.error = nil
        } catch is CancellationError {
          return
        } catch {
          guard self.sessionGeneration == generation else { return }
          self.error = self.message(error)
        }
        self.publishStatus()
      }
    }
  }

  // A lazy window avoids opening an editor at every login on macOS 13 and 14,
  // where SwiftUI's defaultLaunchBehavior(.suppressed) is unavailable.
  func showProfiles() {
    if profilesWindow == nil {
      let window = NSWindow(contentViewController: NSHostingController(rootView: ProfilesView(model: self)))
      window.title = "Resolution Profiles"
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
      window.isReleasedWhenClosed = false
      window.setContentSize(NSSize(width: 680, height: 440))
      window.center()
      profilesWindow = window
    }
    profilesWindow?.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  func start() async {
    guard !hasStarted, !isShuttingDown else { return }
    observeSessionChanges()
    refresh()
    hasStarted = true
    do {
      document = try store.read()
      // Import and replace the earlier CLI-owned LaunchAgent without losing its settings.
      if let legacyAgentURL, FileManager.default.fileExists(atPath: legacyAgentURL.path) {
        let data = try Data(contentsOf: legacyAgentURL)
        let legacy = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        if let arguments = legacy?["ProgramArguments"] as? [String], arguments.count >= 4,
           let width = Int(arguments[2]), let height = Int(arguments[3]) {
          func option(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
          }
          let name = option("--name") ?? "Remote"
          let rate = option("--refresh-rate").flatMap(Double.init) ?? 60
          let existing = document.profiles.first { $0.width == width && $0.height == height && $0.refreshRate == rate }
          let profile = existing ?? ResolutionProfile(name: uniqueName(name), width: width, height: height, refreshRate: rate)
          document = try store.update {
            try $0.upsert(profile)
            $0.activeProfileID = profile.id
          }
          if isSessionActive {
            try await activate(profile.id)
          } else {
            try VirtualAgent.remove()
          }
          // Preserve the old user's opt-in to startup across migration.
          try setLoginEnabled(true)
        }
      } else if isSessionActive, let id = document.activeProfileID {
        try await activate(id)
      }
    } catch { self.error = message(error) }
    guard !isShuttingDown else { return }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    publishStatus()
  }

  private func uniqueName(_ proposed: String) -> String {
    var name = proposed
    var index = 2
    while document.profiles.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
      name = "\(proposed) \(index)"; index += 1
    }
    return name
  }

  func refresh() {
    updateSessionActivity(sessionActivity())
    do {
      let saved = try store.read()
      if saved.profiles != document.profiles || saved.activeProfileID != document.activeProfileID {
        document = saved
      }
      let names = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
        return (id, screen.localizedName)
      })
      let active = try Video.listActiveDisplays()
      if let normal = active.first(where: { !Video.isManagedVirtualDisplay($0) }) {
        defaultResolution = "\(CGDisplayPixelsWide(normal)) × \(CGDisplayPixelsHigh(normal))"
        UserDefaults.standard.set(defaultResolution, forKey: "defaultResolution")
      } else if let saved = UserDefaults.standard.string(forKey: "defaultResolution") {
        defaultResolution = saved
      }
      let physical = active.filter {
        CGDisplayIsBuiltin($0) == 0 && !Video.isManagedVirtualDisplay($0)
      }.map { PhysicalDisplay(id: $0, name: names[$0] ?? "Display \($0)") }
      if physical != physicalDisplays { physicalDisplays = physical }
      lastDisabledID = DisplayController.lastDisabledDisplayID
      loginEnabled = SMAppService.mainApp.status == .enabled
      loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    } catch { self.error = message(error) }
  }

  func activate(_ id: UUID) async throws {
    guard !isShuttingDown else { throw CancellationError() }
    updateSessionActivity(sessionActivity())
    guard isSessionActive else { throw sessionFailure }
    guard !isChanging else { throw DisplayFailure("A display change is already in progress. Try again shortly.") }
    let generation = sessionGeneration
    isChanging = true
    defer { isChanging = false }
    let latest = try store.read()
    guard let profile = latest.profiles.first(where: { $0.id == id }) else { throw DisplayFailure("The profile no longer exists.") }
    try profile.validate()
    if activeProfile == profile, let display, displayReady(display.displayID, profile) { return }
    // Keep the current screen until creation and persistence of its replacement succeed.
    let replacement = try createDisplay(profile)
    pendingDisplay = replacement
    defer {
      if pendingDisplay === replacement { pendingDisplay = nil }
    }
    func requireActiveSession() throws {
      try Task.checkCancellation()
      guard !isShuttingDown, generation == sessionGeneration else { throw sessionFailure }
      updateSessionActivity(sessionActivity())
      guard isSessionActive, generation == sessionGeneration else { throw sessionFailure }
    }
    do {
      var ready = false
      // CoreGraphics publishes the new mode asynchronously. Yield the main
      // actor so display events and the menu remain responsive while waiting.
      for _ in 0..<100 {
        try requireActiveSession()
        if displayReady(replacement.displayID, profile) {
          ready = true; break
        }
        try await Task.sleep(for: .milliseconds(50))
      }
      try requireActiveSession()
      guard ready else {
        let id = replacement.displayID
        let observed = "\(CGDisplayPixelsWide(id)) × \(CGDisplayPixelsHigh(id))"
        throw DisplayFailure("macOS did not activate the requested \(profile.width) × \(profile.height) display in this login session (observed \(observed)). Another login or remote desktop session may own the displays.")
      }
      if let legacyAgentURL, FileManager.default.fileExists(atPath: legacyAgentURL.path) { try VirtualAgent.remove() }
      document = try store.update {
        guard $0.profiles.contains(profile) else { throw DisplayFailure("The profile changed during activation. Try again.") }
        $0.activeProfileID = profile.id
      }
    } catch {
      replacement.invalidate()
      throw error
    }
    display?.invalidate()
    display = replacement
    activeProfile = profile
    error = nil
    publishStatus()
    refresh()
  }

  func off() throws {
    guard !isChanging else { throw DisplayFailure("Wait for the current display change to finish.") }
    document = try store.update { $0.activeProfileID = nil }
    display?.invalidate(); display = nil; activeProfile = nil; error = nil
    publishStatus(); refresh()
  }

  func save(_ profile: ResolutionProfile) throws {
    guard !isChanging else { throw DisplayFailure("Wait for the current display change to finish.") }
    if activeProfile?.id == profile.id { throw DisplayFailure("Select Default before editing this profile.") }
    document = try store.update { try $0.upsert(profile) }
  }

  func delete(_ id: UUID) throws { document = try store.update { try $0.remove(id: id) } }
  func setLoginEnabled(_ enabled: Bool) throws {
    if enabled { try SMAppService.mainApp.register() }
    else { try SMAppService.mainApp.unregister() }
    refresh()
  }

  func toggle(_ id: CGDirectDisplayID? = nil) {
    perform {
      updateSessionActivity(sessionActivity())
      guard isSessionActive else { throw sessionFailure }
      guard let target = id ?? physicalDisplays.first?.id ?? lastDisabledID else {
        throw DisplayFailure("No physical external display is available to toggle.")
      }
      try DisplayController.toggle(id: target); refresh()
    }
  }

  func perform(_ operation: () throws -> Void) {
    do { try operation(); error = nil }
    catch { self.error = message(error) }
    publishStatus()
  }

  func performAsync(_ operation: @escaping @MainActor () async throws -> Void) {
    Task {
      do { try await operation(); error = nil }
      catch { self.error = message(error) }
      publishStatus()
    }
  }

  func handle(_ url: URL) async {
    do {
      let request = try AppRequest(url: url)
      var failure: String?
      do {
        switch request.action {
        case .activate: try await activate(request.profileID!)
        case .off: try off()
        case .status: refresh()
        }
      } catch { failure = message(error); self.error = failure }
      publishStatus()
      try FileManager.default.createDirectory(at: store.requestsDirectory, withIntermediateDirectories: true)
      let responseURL = store.requestsDirectory.appendingPathComponent("\(request.requestID.uuidString).json")
      try JSONEncoder().encode(AppResponse(status: status, error: failure)).write(to: responseURL, options: .atomic)
    } catch { self.error = message(error); publishStatus() }
  }

  func shutdown() {
    isShuttingDown = true
    sessionGeneration &+= 1
    restoreTask?.cancel()
    let center = NSWorkspace.shared.notificationCenter
    for observer in sessionObservers { center.removeObserver(observer) }
    sessionObservers.removeAll()
    timer?.invalidate()
    pendingDisplay?.invalidate(); pendingDisplay = nil
    display?.invalidate(); display = nil; activeProfile = nil
    try? FileManager.default.removeItem(at: store.statusURL)
  }

  private func publishStatus() {
    guard !isShuttingDown else { return }
    do {
      try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
      try JSONEncoder().encode(status).write(to: store.statusURL, options: .atomic)
    } catch { self.error = message(error) }
  }

  private func message(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
  }
}
