import AppKit
import DisplayCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = MenuModel()
  private var startup: Task<Void, Never>?
  func applicationDidFinishLaunching(_ notification: Notification) {
    startup = Task { await model.start() }
  }
  func application(_ application: NSApplication, open urls: [URL]) {
    Task {
      await startup?.value
      for url in urls { await model.handle(url) }
    }
  }
  func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct DisplayMenu: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  var body: some Scene {
    MenuBarExtra("MacDisplayTool", systemImage: "display") {
      DisplayMenuContents(model: delegate.model)
    }
    .menuBarExtraStyle(.menu)
  }
}

struct DisplayMenuContents: View {
  @ObservedObject var model: MenuModel

  var body: some View {
    Group {
      if !model.isSessionActive {
        Text("Resolution paused: inactive login session")
      }
      if model.isChanging {
        Text("Changing resolution…")
      }
      Picker("Resolution", selection: Binding<UUID?>(
        get: { model.document.activeProfileID },
        set: { id in
          if let id {
            model.performAsync { try await model.activate(id) }
          } else {
            model.perform { try model.off() }
          }
        }
      )) {
        Text("Default").tag(Optional<UUID>.none).help(model.defaultResolution)
        ForEach(model.document.profiles) { profile in
          Text(profile.name).tag(Optional(profile.id)).help(profile.detail)
            .disabled(!model.isSessionActive)
        }
      }
      .pickerStyle(.inline)
      .disabled(model.isChanging)

      Divider()
      Button { model.toggle() } label: {
        Label("Toggle display", systemImage: "power")
      }
      .disabled(model.isChanging || !model.isSessionActive || (model.physicalDisplays.isEmpty && model.lastDisabledID == nil))
      if !model.physicalDisplays.isEmpty || model.lastDisabledID != nil {
        Menu("Physical displays") {
          ForEach(model.physicalDisplays) { display in
            Button("Disconnect \(display.name)") { model.toggle(display.id) }
          }
          if let id = model.lastDisabledID, !model.physicalDisplays.contains(where: { $0.id == id }) {
            Button("Reconnect Display \(id)") { model.toggle(id) }
          }
        }
        .disabled(model.isChanging || !model.isSessionActive)
      }

      Divider()
      Toggle("Launch at login", isOn: Binding(
        get: { model.loginEnabled },
        set: { enabled in model.perform { try model.setLoginEnabled(enabled) } }
      ))
      if model.loginNeedsApproval {
        Button("Approve in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
      }
      if let error = model.error {
        Button {
          let alert = NSAlert()
          alert.messageText = "Display change failed"
          alert.informativeText = error
          alert.runModal()
        } label: {
          Label("Display change failed…", systemImage: "exclamationmark.triangle")
        }
      }
      Button("Profiles…") { model.showProfiles() }
      Divider()
      Button("Quit") { NSApplication.shared.terminate(nil) }
        .keyboardShortcut("q")
    }
  }
}
