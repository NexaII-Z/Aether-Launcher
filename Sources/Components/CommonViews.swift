import SwiftUI

/// Scrollable, width-limited page container so iPad layouts stay readable.
struct Screen<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 36)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .aetherScreen()
    }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 8)
    }
}

struct StatusCard: View {
    @EnvironmentObject private var bridge: MinecraftBridge

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .shadow(color: color.opacity(0.8), radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                Text(subtitle).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch bridge.status {
        case .installed: return Theme.accent
        case .notInstalled: return Theme.warning
        case .unknown: return .gray
        }
    }

    private var title: String {
        switch bridge.status {
        case .installed: return "Minecraft is ready"
        case .notInstalled: return "Minecraft not found"
        case .unknown: return "Checking for Minecraft"
        }
    }

    private var subtitle: String {
        switch bridge.status {
        case .installed: return "Detected through the minecraft:// link"
        case .notInstalled: return "Install the official app from the App Store"
        case .unknown: return "One moment"
        }
    }
}

/// Primary call to action. Opens Minecraft, or the App Store page when it isn't installed.
struct LaunchButton: View {
    @EnvironmentObject private var bridge: MinecraftBridge
    @AppStorage(SettingsKey.confirmLaunch) private var confirmLaunch = false
    @State private var confirming = false

    var body: some View {
        Button {
            Haptics.tap()
            switch bridge.status {
            case .installed:
                if confirmLaunch { confirming = true } else { launch() }
            case .notInstalled:
                Task { await bridge.openAppStore() }
            case .unknown:
                bridge.refresh()
            }
        } label: {
            Label(bridge.status == .notInstalled ? "Get Minecraft" : "Play Minecraft",
                  systemImage: bridge.status == .notInstalled ? "arrow.down.app.fill" : "play.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
        .confirmationDialog("Open Minecraft?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Open Minecraft") { launch() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AETHER hands off to the official Minecraft app.")
        }
    }

    private func launch() {
        Task { await bridge.launch() }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct BulletList: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(y: -2)
                    Text(line).font(.subheadline).foregroundStyle(.white.opacity(0.86))
                }
            }
        }
    }
}
