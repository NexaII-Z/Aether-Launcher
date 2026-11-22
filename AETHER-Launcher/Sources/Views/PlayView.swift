import SwiftUI

struct PlayView: View {
    @EnvironmentObject private var bridge: MinecraftBridge
    @AppStorage(SettingsKey.confirmLaunch) private var confirmLaunch = false

    var body: some View {
        Screen {
            ScreenHeader(title: "Play", subtitle: "Opens the official Minecraft app")

            VStack(spacing: 18) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 18)
                    .padding(.top, 6)
                Text(headline)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                LaunchButton()
                resultLine
            }
            .frame(maxWidth: .infinity)
            .glassCard(radius: 28, padding: 22)

            Toggle(isOn: $confirmLaunch) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask before opening").font(.system(.body, design: .rounded).weight(.medium))
                    Text("Shows a confirmation before the hand-off.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)
            .glassCard(radius: 22, padding: 16)

            if bridge.status == .notInstalled {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Minecraft isn't installed")
                        .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                    BulletList(lines: [
                        "Install Minecraft from the App Store with the Apple ID you bought it with.",
                        "Open it once so iOS registers its link, then come back and tap Check again on the Installation screen."
                    ])
                }
                .glassCard()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var headline: String {
        switch bridge.status {
        case .installed: return "Ready when you are"
        case .notInstalled: return "Minecraft not found"
        case .unknown: return "Checking for Minecraft"
        }
    }

    @ViewBuilder
    private var resultLine: some View {
        switch bridge.lastLaunch {
        case .some(.opened(let date)):
            Label("Handed off to Minecraft at \(date.formatted(date: .omitted, time: .shortened))",
                  systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.accent)
        case .some(.failed(let message)):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.warning)
                .multilineTextAlignment(.leading)
        case .none:
            EmptyView()
        }
    }
}
