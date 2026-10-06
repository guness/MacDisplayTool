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
    .menuBarExtraStyle(.window)
  }
}

struct DisplayMenuContents: View {
  @ObservedObject var model: MenuModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Image(systemName: "display")
          .font(.system(size: 19, weight: .medium))
          .foregroundStyle(Color.accentColor)
          .frame(width: 38, height: 38)
          .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 3) {
          Text("MacDisplayTool").font(.headline)
          Text(model.isChanging ? "Changing resolution…" : model.activeProfile?.name ?? "Default")
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        if model.isChanging { ProgressView().controlSize(.small) }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("RESOLUTION").font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary).padding(.horizontal, 8)
        ScrollView {
          VStack(spacing: 3) {
            ResolutionRow(title: "Default", detail: model.defaultResolution,
                          selected: model.activeProfile == nil) {
              model.perform { try model.off() }
            }
            ForEach(model.document.profiles) { profile in
              ResolutionRow(title: profile.name, detail: profile.detail,
                            selected: model.activeProfile?.id == profile.id) {
                model.performAsync { try await model.activate(profile.id) }
              }
            }
          }
        }
        .scrollIndicators(.hidden)
        .frame(height: min(CGFloat(model.document.profiles.count + 1) * 57, 250))
        .disabled(model.isChanging)
      }

      Divider()
      HStack(spacing: 8) {
        Button { model.toggle() } label: {
          Label("Toggle display", systemImage: "power")
            .frame(maxWidth: .infinity)
        }
        .disabled(model.physicalDisplays.isEmpty && model.lastDisabledID == nil)
        if !model.physicalDisplays.isEmpty || model.lastDisabledID != nil {
          Menu {
            ForEach(model.physicalDisplays) { display in
              Button("Disconnect \(display.name)") { model.toggle(display.id) }
            }
            if let id = model.lastDisabledID, !model.physicalDisplays.contains(where: { $0.id == id }) {
              Button("Reconnect Display \(id)") { model.toggle(id) }
            }
          } label: { Image(systemName: "display.2") }
            .accessibilityLabel("Physical displays")
        }
      }
      .buttonStyle(.bordered).controlSize(.regular)
      .disabled(model.isChanging)

      Toggle(isOn: Binding(get: { model.loginEnabled }, set: { enabled in
        model.perform { try model.setLoginEnabled(enabled) }
      })) {
        Text("Launch at login").frame(maxWidth: .infinity, alignment: .leading)
      }
      .font(.callout).toggleStyle(.switch).controlSize(.small)
      if model.loginNeedsApproval {
        Button("Approve in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
          .font(.caption)
      }
      if let error = model.error {
        Button {
          let alert = NSAlert(); alert.messageText = "Display change failed"; alert.informativeText = error
          alert.runModal()
        } label: {
          Label("Display change failed", systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange)
        }.buttonStyle(.plain).help(error)
      }
      Divider()
      HStack {
        Button { model.showProfiles() } label: { Label("Profiles…", systemImage: "slider.horizontal.3") }
        Spacer()
        Button("Quit") { NSApplication.shared.terminate(nil) }
          .keyboardShortcut("q")
      }
      .font(.callout).buttonStyle(.plain).foregroundStyle(.secondary)
    }
    .padding(16)
    .frame(width: 320)
  }
}

struct ResolutionRow: View {
  let title: String
  let detail: String
  let selected: Bool
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(.primary).lineLimit(1)
          Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 8)
        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
      }
      .padding(.horizontal, 10).frame(height: 54)
      .contentShape(RoundedRectangle(cornerRadius: 8))
      .background(selected ? Color.accentColor.opacity(0.1) : hovering ? Color.primary.opacity(0.05) : .clear,
                  in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityLabel("\(title), \(detail)")
    .accessibilityValue(selected ? "Selected" : "")
  }
}
