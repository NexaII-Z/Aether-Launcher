import SwiftUI

struct AboutView: View {
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 6) {
                Text("AETHER Launcher")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Version \(versionText)")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("How it works").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                BulletList(lines: [
                    "Play opens the official Minecraft app through its minecraft:// link.",
                    "Packs, worlds and add-ons live in AETHER's own library, then reach Minecraft through the system Open In menu.",
                    "Discover downloads from CurseForge with your own API key. Downloads are validated before they enter the library.",
                    "Client features are saved settings. They can't act on Minecraft because iOS doesn't allow code to run inside another app."
                ])
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("iOS limits").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                BulletList(lines: [
                    "AETHER can't run Minecraft inside itself, draw over it, change its camera, or read or write its sandbox. See the technical report in the repository.",
                    "It can't see Minecraft's version or confirm that an import finished. Minecraft shows its own import progress.",
                    "Worlds and packs only reach Minecraft when you pick it in the Open In menu."
                ])
            }
            .glassCard()

            Text("AETHER is an unofficial companion app. It is not made by, affiliated with, or endorsed by Mojang Studios or Microsoft. Minecraft is a trademark of Mojang Synergies AB.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            if let url = URL(string: "https://www.minecraft.net/en-us/usage-guidelines") {
                Link(destination: url) {
                    Label("Minecraft usage guidelines", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
