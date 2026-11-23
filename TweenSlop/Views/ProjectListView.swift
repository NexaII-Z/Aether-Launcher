import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject var store: ProjectStore
    @State private var path: [UUID] = []
    @State private var showNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.projects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.walk.motion")
                            .font(.system(size: 56))
                            .foregroundColor(.red)
                        Text("No projects yet").font(.title3.bold())
                        Text("Create a project, add a body, import its parts, set pivots and animate.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 32)
                        Button("New Project") { newName = ""; showNew = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(store.projects) { p in
                            NavigationLink(value: p.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.headline)
                                    Text("\(p.bodies.count) bodies · \(p.fps) fps · \(p.durationFrames) frames")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { idx in
                            let items = idx.map { store.projects[$0] }
                            for p in items { store.delete(p) }
                        }
                    }
                }
            }
            .navigationTitle("TweenSlop")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { newName = ""; showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let p = store.projects.first(where: { $0.id == id }) {
                    EditorView(project: p, store: store)
                }
            }
            .alert("New Project", isPresented: $showNew) {
                TextField("Project name", text: $newName)
                Button("Create") {
                    let p = store.create(name: newName)
                    path.append(p.id)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
