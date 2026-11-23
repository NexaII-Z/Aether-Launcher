import SwiftUI
import UIKit

/// Configures the in-game zoom button and hands the values to the "Patch Minecraft IPA" GitHub workflow.
/// AETHER itself never touches the Minecraft app: the patch happens on a GitHub runner against your own IPA.
struct PatchStudioView: View {
    @EnvironmentObject private var features: FeatureManager
    @Environment(\.openURL) private var openURL
    @AppStorage("patch.repo") private var repo = ""
    @State private var copied = false

    private var strength: Double { features.double("zoom", "strength", default: 3) }
    private var buttonSize: Double { features.double("zoom", "buttonSize", default: 54) }
    private var opacity: Double { features.double("zoom", "opacity", default: 0.9) }

    private var summary: String {
        "zoom_strength: \(format(strength))\nbutton_size: \(Int(buttonSize))\nbutton_opacity: \(String(format: "%.2f", opacity))"
    }

    private var actionsURL: URL? {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/")
        guard parts.count == 2, !trimmed.contains(" ") else { return nil }
        return URL(string: "https://github.com/\(trimmed)/actions/workflows/patch-ipa.yml")
    }

    var body: some View {
        Screen {
            ScreenHeader(title: "Patch Studio", subtitle: "In-game zoom button")

            VStack(alignment: .leading, spacing: 12) {
                Label("How it works", systemImage: "wand.and.stars")
                    .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                Text("iOS won't let one app draw inside another, so the button is added to your own Minecraft install: a small library (AetherZoom) is placed inside the IPA before it's signed. It adds no packs or mods, reads no game memory, and the zoom is a screen magnification, not a field-of-view change.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 14) {
                Text("Button settings").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                sliderRow("Zoom strength", value: strength, text: "\(format(strength))x", option: "strength", range: 1.5...8, step: 0.5, fallback: 3)
                sliderRow("Button size", value: buttonSize, text: "\(Int(buttonSize)) pt", option: "buttonSize", range: 36...80, step: 2, fallback: 54)
                sliderRow("Button opacity", value: opacity, text: String(format: "%.2f", opacity), option: "opacity", range: 0.3...1, step: 0.05, fallback: 0.9)
                Text("In game: tap the button to zoom in or out, drag it to move it, hold it to change the strength.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("Run the patch").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                TextField("owner/repository (your private repo)", text: $repo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    .foregroundStyle(.white)
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = summary
                        Haptics.success()
                        copied = true
                    } label: { Label(copied ? "Copied" : "Copy values", systemImage: "doc.on.doc") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button {
                        if let url = actionsURL { Haptics.tap(); openURL(url) } else { Haptics.failure() }
                    } label: { Label("Open workflow", systemImage: "arrow.up.right.square") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(actionsURL == nil)
                }
                Text(actionsURL == nil ? "Enter your repository as owner/name to enable Open workflow." : "Opens GitHub. Choose Run workflow and paste the copied values.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 10) {
                Text("Steps").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                BulletList(lines: [
                    "In your private repository, create a release tagged minecraft-ipa and attach your own Minecraft IPA.",
                    "Run Actions > Patch Minecraft IPA with the values above.",
                    "Download the artifact and sign it (see docs/SIGNING.md), or turn on the workflow's sign option.",
                    "Install it and open the game: the zoom button appears above gameplay."
                ])
                Text("AETHER never decrypts apps. A still-encrypted binary is refused.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            .glassCard()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func format(_ value: Double) -> String { String(format: "%.1f", value) }

    private func sliderRow(_ title: String, value: Double, text: String, option: String, range: ClosedRange<Double>, step: Double, fallback: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.white)
                Spacer()
                Text(text).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondaryText)
            }
            Slider(value: Binding(
                get: { features.double("zoom", option, default: fallback) },
                set: { copied = false; features.set($0, "zoom", option) }
            ), in: range, step: step)
        }
    }
}
