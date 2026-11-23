import SwiftUI
import UniformTypeIdentifiers

enum ImportTarget {
    case partImage(UUID)
    case sound
    case video
}

struct EditorView: View {
    @StateObject private var model: EditorModel
    @State private var importTarget: ImportTarget?
    @State private var showImporter = false

    init(project: Project, store: ProjectStore) {
        _model = StateObject(wrappedValue: EditorModel(project: project, store: store))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                StageView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                Picker("", selection: $model.tab) {
                    ForEach(PanelTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(8)
                Group {
                    switch model.tab {
                    case .rig: RigPanel(model: model, requestImport: request)
                    case .animate: AnimatePanel(model: model)
                    case .media: MediaPanel(model: model, requestImport: request)
                    }
                }
                .frame(height: geo.size.height * 0.42)
            }
        }
        .navigationTitle(model.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if model.isPlaying { model.pause() } else { model.play() }
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: importTypes) { result in
            handleImport(result)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay {
            if model.isBusy {
                ProgressView("Working…")
                    .padding()
                    .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onDisappear { model.commit() }
    }

    private func request(_ t: ImportTarget) {
        importTarget = t
        showImporter = true
    }

    private var importTypes: [UTType] {
        switch importTarget {
        case .some(.partImage): return [.image]
        case .some(.sound): return [.audio, .movie]
        case .some(.video): return [.movie]
        case .none: return [.item]
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard let target = importTarget else { return }
        importTarget = nil
        switch result {
        case .failure(let e):
            if (e as? CocoaError)?.code == .userCancelled { return }
            model.errorMessage = e.localizedDescription
        case .success(let url):
            switch target {
            case .partImage(let id):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    model.importImage(data: data, partID: id)
                } else {
                    model.errorMessage = "Couldn't read that file."
                }
            case .sound:
                Task { @MainActor in await model.importSound(from: url) }
            case .video:
                Task { @MainActor in await model.importVideo(from: url) }
            }
        }
    }
}
