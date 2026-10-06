import DisplayCore
import SwiftUI

struct ProfilesView: View {
  @ObservedObject var model: MenuModel
  @State private var selection: UUID?
  @State private var draftID = UUID()
  @State private var name = ""
  @State private var width = "2732"
  @State private var height = "2048"
  @State private var rate = "60"
  @State private var formError: String?
  @FocusState private var nameFocused: Bool
  private var isEditingActive: Bool { selection != nil && model.activeProfile?.id == selection }

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        List(selection: $selection) {
          ForEach(model.document.profiles) { profile in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(profile.name).fontWeight(.medium)
                if model.activeProfile?.id == profile.id {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Active")
                }
              }
              Text(profile.detail).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 4).tag(profile.id)
          }
        }
        Divider()
        HStack {
          Button { newProfile() } label: { Image(systemName: "plus") }
            .accessibilityLabel("Add resolution profile")
          Button {
            guard let selection else { return }
            model.perform { try model.delete(selection) }
            if !model.document.profiles.contains(where: { $0.id == selection }) { newProfile() }
          } label: { Image(systemName: "minus") }
            .accessibilityLabel("Delete selected resolution profile")
            .disabled(selection == nil || model.activeProfile?.id == selection)
          Spacer()
        }.padding(10)
      }.frame(width: 240)
      Divider()
      VStack(alignment: .leading, spacing: 18) {
        Text(selection == nil ? "New Resolution Profile" : "Edit Resolution Profile").font(.title2).fontWeight(.semibold)
        Text("Choose the pixel dimensions your remote screen needs.")
          .font(.callout).foregroundStyle(.secondary)
        Form {
          TextField("Name", text: $name).focused($nameFocused)
          TextField("Width (pixels)", text: $width)
          TextField("Height (pixels)", text: $height)
          TextField("Refresh rate (Hz)", text: $rate)
        }.textFieldStyle(.roundedBorder)
        if isEditingActive {
          Text("Select Default to edit this profile.").font(.callout).foregroundStyle(.secondary)
        }
        if let error = formError ?? model.error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        Spacer(minLength: 0)
        HStack {
          Button("Save Profile") { Task { await save(activate: false) } }
            .disabled(isEditingActive || model.isChanging)
          Spacer()
          if isEditingActive {
            Button("Default") { model.perform { try model.off() } }.disabled(model.isChanging)
          } else {
            Button("Save and Activate") { Task { await save(activate: true) } }
              .buttonStyle(.borderedProminent).disabled(model.isChanging)
          }
        }
      }.padding(24)
    }
    .frame(minWidth: 650, minHeight: 400)
    .onChange(of: selection) { id in load(id) }
  }

  private func newProfile() {
    selection = nil; draftID = UUID(); name = ""; width = "2732"; height = "2048"; rate = "60"; formError = nil; nameFocused = true
  }
  private func load(_ id: UUID?) {
    guard let profile = model.document.profiles.first(where: { $0.id == id }) else { return }
    draftID = profile.id; name = profile.name; width = String(profile.width); height = String(profile.height)
    rate = String(profile.refreshRate); formError = nil
  }
  private func save(activate: Bool) async {
    do {
      guard let width = Int(width), let height = Int(height), let rate = Double(rate) else {
        throw DisplayFailure("Enter whole pixel dimensions and a numeric refresh rate.")
      }
      let profile = ResolutionProfile(id: draftID, name: name, width: width, height: height, refreshRate: rate)
      try model.save(profile)
      selection = profile.id
      if activate { try await model.activate(profile.id) }
      formError = nil
    } catch { formError = (error as? LocalizedError)?.errorDescription ?? String(describing: error) }
  }
}
