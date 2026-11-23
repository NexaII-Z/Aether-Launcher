import SwiftUI

struct AnimatePanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Button {
                        if model.isPlaying { model.pause() } else { model.play() }
                    } label: {
                        Pill(title: model.isPlaying ? "Pause" : "Play", icon: model.isPlaying ? "pause.fill" : "play.fill")
                    }
                    Text("Frame \(model.currentFrame) / \(model.project.durationFrames - 1)")
                        .font(.footnote.monospacedDigit())
                    Spacer()
                    Text(String(format: "%.2fs", Double(model.currentFrame) / Double(max(model.project.fps, 1))))
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(model.currentFrame) },
                        set: { model.scrub(Int($0.rounded())) }
                    ),
                    in: 0...Double(max(model.project.durationFrames - 1, 1))
                )
                KeyframeStrip(model: model)

                HStack {
                    Button { model.jumpKey(forward: false) } label: { Pill(title: "Prev", icon: "backward.end.fill") }
                    Button { model.addKeyframeHere() } label: { Pill(title: "Key", icon: "diamond.fill") }
                    Button { model.jumpKey(forward: true) } label: { Pill(title: "Next", icon: "forward.end.fill") }
                    Spacer()
                    Button(role: .destructive) { model.deleteKeyframeHere() } label: { Pill(title: "Delete", icon: "trash") }
                        .disabled(model.keyAtCurrent == nil)
                }

                HStack {
                    Text("Tween").font(.footnote).foregroundColor(.secondary)
                    Picker("Easing", selection: Binding(
                        get: { model.keyAtCurrent?.easing ?? .easeInOut },
                        set: { model.setEasingHere($0) }
                    )) {
                        ForEach(Easing.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .disabled(model.keyAtCurrent == nil)
                    Spacer()
                    Button(role: .destructive) { model.clearKeyframes() } label: {
                        Text("Clear part keys").font(.footnote)
                    }
                }

                Picker("Tool", selection: $model.poseTool) {
                    ForEach(PoseTool.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if let part = model.selectedPart {
                    HStack {
                        Text("Scale").font(.caption).foregroundColor(.secondary)
                        Slider(
                            value: Binding(
                                get: { Rig.pose(for: part, at: model.currentFrame).scale },
                                set: { v in model.editPose(partID: part.id) { $0.scale = v } }
                            ),
                            in: 0.2...3
                        )
                    }
                }
                PartChips(model: model)
                Text("Moving a part keys it at the current frame. Children follow their parent.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }
}
