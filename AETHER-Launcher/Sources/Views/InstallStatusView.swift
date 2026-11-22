import SwiftUI

struct InstallStatusView: View {
    @EnvironmentObject private var bridge: MinecraftBridge

    var body: some View {
        Screen {
            StatusCard()

            VStack(alignment: .leading, spacing: 14) {
                InfoRow(label: "Status", value: statusText)
                Divider().overlay(Theme.hairline)
                InfoRow(label: "Detected through", value: "\(MinecraftBridge.scheme)://")
                Divider().overlay(Theme.hairline)
                InfoRow(label: "Expected app", value: MinecraftBridge.bundleIdentifier)
                Divider().overlay(Theme.hairline)
                InfoRow(label: "Last checked", value: lastCheckedText)
            }
            .glassCard()

            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    bridge.refresh()
                } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    Haptics.tap()
                    Task { await bridge.openAppStore() }
                } label: {
                    Label("App Store page", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("What this check can and can't see")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                BulletList(lines: [
                    "iOS only tells AETHER whether some app answers to the minecraft:// link. It can't read the installed version or the app's bundle ID.",
                    "Minecraft's files live in its own sandbox. AETHER can't browse them; it hands files over through the system Open In menu instead.",
                    "If the status is wrong right after an install, open Minecraft once and check again."
                ])
            }
            .glassCard()
        }
        .navigationTitle("Installation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var statusText: String {
        switch bridge.status {
        case .installed: return "Installed"
        case .notInstalled: return "Not found"
        case .unknown: return "Unknown"
        }
    }

    private var lastCheckedText: String {
        guard let date = bridge.lastChecked else { return "Never" }
        return date.formatted(date: .omitted, time: .standard)
    }
}
