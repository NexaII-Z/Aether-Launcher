import SwiftUI
import PhotosUI

struct RigPanel: View {
    @ObservedObject var model: EditorModel
    let requestImport: (ImportTarget) -> Void
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                bodyRow
                if let body = model.selectedBody {
                    bodySettings(body)
                    Picker("Tool", selection: $model.rigTool) {
                        ForEach(RigTool.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    PartChips(model: model)
                    if let part = model.selectedPart {
                        inspector(part, body: body)
                    }
                    Button { model.addPart() } label: { Pill(title: "Add Part", icon: "plus") }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private var bodyRow: some View {
        HStack {
            if model.project.bodies.isEmpty {
                Text("No bodies yet").foregroundColor(.secondary)
            } else {
                Menu {
                    ForEach(model.project.bodies) { b in
                        Button(b.name) { model.selectBody(b.id) }
                    }
                } label: {
                    Pill(title: model.selectedBody?.name ?? "Body", icon: "figure.stand")
                }
            }
            Spacer()
            Menu {
                Button("New Humanoid Body") { model.addBody(humanoid: true) }
                Button("New Empty Body") { model.addBody(humanoid: false) }
            } label: {
                Pill(title: "New Body", icon: "plus.circle")
            }
        }
    }

    private func bodySettings(_ body: PuppetBody) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Body name", text: Binding(
                    get: { body.name },
                    set: { v in model.mutateBody { $0.name = v } }
                ))
                .textFieldStyle(.roundedBorder)
                Button(role: .destructive) { model.deleteSelectedBody() } label: {
                    Image(systemName: "trash")
                }
            }
            HStack {
                Text("Body scale").font(.caption).foregroundColor(.secondary)
                Slider(value: Binding(
                    get: { body.scale },
                    set: { v in model.mutateBody { $0.scale = v } }
                ), in: 0.1...3)
            }
        }
    }

    private func inspector(_ part: Part, body: PuppetBody) -> some View {
        let blocked = Rig.descendants(of: part.id, in: body.parts)
        let candidates = body.parts.filter { $0.id != part.id && !blocked.contains($0.id) }
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Part name", text: Binding(
                    get: { part.name },
                    set: { v in model.mutatePart(part.id) { $0.name = v } }
                ))
                .textFieldStyle(.roundedBorder)

                HStack {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Pill(title: "Photos", icon: "photo")
                    }
                    Button { requestImport(.partImage(part.id)) } label: {
                        Pill(title: "Files", icon: "folder")
                    }
                    if part.imageFile != nil {
                        Button(role: .destructive) {
                            model.mutatePart(part.id) { $0.imageFile = nil }
                        } label: {
                            Pill(title: "Clear", icon: "xmark")
                        }
                    }
                }
                .onChange(of: pickerItem) { item in
                    guard let item = item, let id = model.selectedPartID else { return }
                    Task { @MainActor in
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            model.importImage(data: data, partID: id)
                        } else {
                            model.errorMessage = "Couldn't load that photo."
                        }
                        pickerItem = nil
                    }
                }

                Picker("Parent", selection: Binding<UUID?>(
                    get: { part.parentID },
                    set: { v in model.setParent(part.id, v) }
                )) {
                    Text("None (root)").tag(Optional<UUID>.none)
                    ForEach(candidates) { c in
                        Text(c.name).tag(Optional(c.id))
                    }
                }

                HStack {
                    Text("Width").font(.caption).frame(width: 50, alignment: .leading)
                    Slider(value: Binding(
                        get: { part.size.x },
                        set: { v in model.mutatePart(part.id) { $0.size.x = v } }
                    ), in: 20...1500)
                }
                HStack {
                    Text("Height").font(.caption).frame(width: 50, alignment: .leading)
                    Slider(value: Binding(
                        get: { part.size.y },
                        set: { v in model.mutatePart(part.id) { $0.size.y = v } }
                    ), in: 20...1500)
                }
                Stepper("Layer: \(part.z)", value: Binding(
                    get: { part.z },
                    set: { v in model.mutatePart(part.id) { $0.z = v } }
                ), in: -20...50)

                Button(role: .destructive) { model.deletePart(part.id) } label: {
                    Label("Delete Part", systemImage: "trash")
                        .font(.footnote)
                }
            }
        }
    }
}
