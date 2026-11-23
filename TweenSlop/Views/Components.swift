import SwiftUI
import AVFoundation

struct Pill: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.12), in: Capsule())
    }
}

struct PartChips: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(model.selectedBody?.parts ?? []) { part in
                    Button {
                        model.selectedPartID = part.id
                    } label: {
                        Text(part.name)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(part.id == model.selectedPartID ? Color.red : Color.white.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }
}

struct KeyframeStrip: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        GeometryReader { geo in
            let span = CGFloat(max(model.project.durationFrames - 1, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1)).frame(height: 6)
                ForEach(model.selectedPart?.keyframes ?? []) { k in
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 14))
                        .foregroundColor(k.frame == model.currentFrame ? .red : .orange)
                        .position(x: CGFloat(k.frame) / span * geo.size.width, y: geo.size.height / 2)
                        .onTapGesture { model.scrub(k.frame) }
                }
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2, height: geo.size.height)
                    .position(x: CGFloat(model.currentFrame) / span * geo.size.width, y: geo.size.height / 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 24)
    }
}

final class PlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}
