import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var bridge: MinecraftBridge
    @EnvironmentObject private var library: PackLibrary
    @Environment(\.openURL) private var openURL

    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.confirmLaunch) private var confirmLaunch = false
    @AppStorage(SettingsKey.autoRefresh) private var autoRefresh = true
    @State private var confirmingClear = false
    @State private var filesMessage: String?

    var body: some View {
        Screen {
            ScreenHeader(title: "Settings", subtitle: "Launcher behaviour and your file library")

            VStack(spacing: 16) {
                toggleRow("Haptic feedback", "Light taps on buttons and results.", $haptics)
                Divider().overlay(Theme.hairline)
                toggleRow("Ask before opening Minecraft", "Shows a confirmation before the hand-off.", $confirmLaunch)
                Divider().overlay(Theme.hairline)
                toggleRow("Re-check Minecraft on return", "Refreshes install status whenever AETHER becomes active.", $autoRefresh)
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 14) {
                Text("Library").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                Text("\(library.items.count) imported file\(library.items.count == 1 ? "" : "s") in AETHER's Documents folder. It also shows up in Files under On My iPhone, AETHER.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                HStack(spacing: 12) {
                    Button {
                        Haptics.tap()
                        if let url = library.filesAppURL {
                            openURL(url) { accepted in
                                if !accepted { filesMessage = "Couldn't open the Files app from here." }
                            }
                        }
                    } label: {
                        Label("Show in Files", systemImage: "folder")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        Haptics.tap()
                        confirmingClear = true
                    } label: {
                        Label("Remove all", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(library.items.isEmpty)
                }
                if let filesMessage {
                    Text(filesMessage).font(.footnote).foregroundStyle(Theme.warning)
                }
            }
            .glassCard()

            VStack(spacing: 0) {
                navRow("Minecraft installation", symbol: "checkmark.seal.fill") { InstallStatusView() }
                Divider().overlay(Theme.hairline).padding(.vertical, 12)
                navRow("About AETHER", symbol: "info.circle.fill") { AboutView() }
            }
            .glassCard()
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Remove every imported file?",
                            isPresented: $confirmingClear,
                            titleVisibility: .visible) {
            Button("Remove all", role: .destructive) { Task { await library.removeAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes AETHER's copies only. Minecraft's own content isn't touched.")
        }
    }

    private func toggleRow(_ title: String, _ detail: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .rounded).weight(.medium)).foregroundStyle(.white)
                Text(detail).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .tint(Theme.accent)
    }

    private func navRow<Destination: View>(_ title: String, symbol: String,
                                           @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 26)
                Text(title).font(.system(.body, design: .rounded).weight(.medium)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}
