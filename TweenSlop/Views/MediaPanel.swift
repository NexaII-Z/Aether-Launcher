import SwiftUI
import PhotosUI

struct MediaPanel: View {
    @ObservedObject var model: EditorModel
    let requestImport: (ImportTarget) -> Void
    @State private var videoItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Timeline") {
                    VStack(alignment: .leading) {
                        Stepper("FPS: \(model.project.fps)", value: Binding(
                            get: { model.project.fps },
                            set: { model.setFPS($0) }
                        ), in: 1...60)
                        Stepper(
                            "Length: \(model.project.durationFrames) frames (\(String(format: "%.1f", Double(model.project.durationFrames) / Double(max(model.project.fps, 1))))s)",
                            value: Binding(
                                get: { model.project.durationFrames },
                                set: { model.setDuration($0) }
                            ),
                            in: 2...7200,
                            step: 6
                        )
                        Menu {
                            Button("1080 × 1920 (9:16)") { model.setCanvas(1080, 1920) }
                            Button("1920 × 1080 (16:9)") { model.setCanvas(1920, 1080) }
                            Button("1080 × 1080 (1:1)") { model.setCanvas(1080, 1080) }
                            Button("1080 × 1350 (4:5)") { model.setCanvas(1080, 1350) }
                        } label: {
                            Pill(title: "Canvas \(Int(model.project.canvasWidth))×\(Int(model.project.canvasHeight))", icon: "aspectratio")
                        }
                    }
                }

                GroupBox("Sounds") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.project.sounds) { s in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "waveform")
                                    Text(s.name).lineLimit(1)
                                    Spacer()
                                    Button(role: .destructive) { model.removeSound(s.id) } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                                Stepper("Starts at frame \(s.startFrame)", value: Binding(
                                    get: { s.startFrame },
                                    set: { v in model.updateSound(s.id) { $0.startFrame = v } }
                                ), in: 0...max(model.project.durationFrames, 1))
                                HStack {
                                    Image(systemName: "speaker.fill")
                                    Slider(value: Binding(
                                        get: { s.volume },
                                        set: { v in model.updateSound(s.id) { $0.volume = v } }
                                    ), in: 0...1)
                                }
                            }
                        }
                        Button { requestImport(.sound) } label: {
                            Pill(title: "Import audio or MP4", icon: "music.note")
                        }
                        Text("MP4/MOV files are converted to an audio track automatically.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                GroupBox("Background video") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let v = model.project.video {
                            HStack {
                                Image(systemName: "film")
                                Text(v.name).lineLimit(1)
                                Spacer()
                                Button(role: .destructive) { model.removeVideo() } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            Stepper("Starts at frame \(v.startFrame)", value: Binding(
                                get: { v.startFrame },
                                set: { model.setVideoStart($0) }
                            ), in: 0...max(model.project.durationFrames, 1))
                            Button {
                                Task { @MainActor in await model.extractVideoAudio() }
                            } label: {
                                Pill(title: "Use video's audio as sound", icon: "waveform.badge.plus")
                            }
                        }
                        HStack {
                            PhotosPicker(selection: $videoItem, matching: .videos) {
                                Pill(title: "From Photos", icon: "photo.on.rectangle")
                            }
                            Button { requestImport(.video) } label: {
                                Pill(title: "From Files", icon: "folder")
                            }
                        }
                        .onChange(of: videoItem) { item in
                            guard let item = item else { return }
                            Task { @MainActor in
                                if let movie = try? await item.loadTransferable(type: MovieFile.self) {
                                    await model.importVideo(from: movie.url)
                                } else {
                                    model.errorMessage = "Couldn't load that video."
                                }
                                videoItem = nil
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
}
