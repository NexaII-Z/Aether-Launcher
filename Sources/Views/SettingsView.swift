import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var library: PackLibrary
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.openURL) private var openURL

    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.confirmLaunch) private var confirmLaunch = false
    @AppStorage(SettingsKey.autoRefresh) private var autoRefresh = true
    @AppStorage(SettingsKey.solidCards) private var solidCards = false
    @AppStorage(DownloadManager.notifyKey) private var notifyDownloads = false
    @State private var confirmingClear = false
    @State private var filesMessage: String?
    @State private var notificationMessage: String?

    var body: some View {
        Screen {
            ScreenHeader(title: "Settings", subtitle: "Launcher behaviour, downloads and storage")

            section("Appearance") {
                toggleRow("Solid cards", "Replaces glass and blur with solid panels. Helps readability and battery.", $solidCards)
            }

            section("Launch") {
                toggleRow("Haptic feedback", "Light taps on buttons and results.", $haptics)
                Divider().overlay(Theme.hairline)
                toggleRow("Ask before opening Minecraft", "Shows a confirmation before the hand-off.", $confirmLaunch)
                Divider().overlay(Theme.hairline)
                toggleRow("Re-check Minecraft on return", "Refreshes install status whenever AETHER becomes active.", $autoRefresh)
            }

            section("Downloads") {
                Toggle(isOn: Binding(get: { notifyDownloads }, set: { setNotifications($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notify when a download finishes").font(.system(.body, design: .rounded).weight(.medium)).foregroundStyle(.white)
                        Text("Downloads pause while AETHER is suspended by iOS.").font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                .tint(Theme.accent)
                if let notificationMessage { Text(notificationMessage).font(.footnote).foregroundStyle(Theme.warning) }
                Divider().overlay(Theme.hairline)
                NavigationLink { DownloadsView() } label: { navLabel("Download history", "arrow.down.circle.fill") }.buttonStyle(.plain)
            }

            section("Library folder") {
                Text("\(library.items.count) file\(library.items.count == 1 ? "" : "s") in AETHER's Documents folder, also visible in Files under On My iPhone, AETHER.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                HStack(spacing: 12) {
                    Button {
                        Haptics.tap()
                        if let url = library.filesAppURL {
                            openURL(url) { accepted in if !accepted { filesMessage = "Couldn't open the Files app from here." } }
                        }
                    } label: { Label("Show in Files", systemImage: "folder") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button { Haptics.tap(); confirmingClear = true } label: { Label("Remove all", systemImage: "trash") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(library.items.isEmpty)
                }
                if let filesMessage { Text(filesMessage).font(.footnote).foregroundStyle(Theme.warning) }
            }

            CurseForgeSetupCard()

            VStack(spacing: 0) {
                NavigationLink { AccountView() } label: { navLabel("Microsoft account", "person.crop.circle.fill") }.buttonStyle(.plain)
                Divider().overlay(Theme.hairline).padding(.vertical, 12)
                NavigationLink { StorageView() } label: { navLabel("Storage and cache", "internaldrive.fill") }.buttonStyle(.plain)
                Divider().overlay(Theme.hairline).padding(.vertical, 12)
                NavigationLink { InstallStatusView() } label: { navLabel("Minecraft installation", "checkmark.seal.fill") }.buttonStyle(.plain)
                Divider().overlay(Theme.hairline).padding(.vertical, 12)
                NavigationLink { RuntimeInvestigationView() } label: { navLabel("Runtime investigation", "doc.text.magnifyingglass") }.buttonStyle(.plain)
                Divider().overlay(Theme.hairline).padding(.vertical, 12)
                NavigationLink { AboutView() } label: { navLabel("About AETHER", "info.circle.fill") }.buttonStyle(.plain)
            }
            .glassCard()
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Remove every imported file?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Remove all", role: .destructive) { Task { await library.removeAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes AETHER's copies only. Minecraft's own content isn't touched.")
        }
    }

    private func setNotifications(_ enabled: Bool) {
        notificationMessage = nil
        guard enabled else { notifyDownloads = false; return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                notifyDownloads = granted
                if !granted { notificationMessage = "Notifications are off for AETHER. Allow them in the iOS Settings app." }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(.white)
            content()
        }
        .glassCard()
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

    private func navLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 26)
            Text(title).font(.system(.body, design: .rounded).weight(.medium)).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
        }
    }
}
