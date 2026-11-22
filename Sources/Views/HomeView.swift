import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: PackLibrary
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var versions: VersionStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var account: AccountManager

    var body: some View {
        Screen {
            HStack(alignment: .top) {
                ScreenHeader(title: "AETHER", subtitle: "Launcher for the official Minecraft Bedrock app")
                Spacer(minLength: 8)
                NavigationLink { AccountView() } label: { accountChip }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
            }

            NavigationLink { InstallStatusView() } label: { StatusCard() }
                .buttonStyle(.plain)

            versionCard

            LaunchButton()

            if !downloads.records.isEmpty { recentDownloads }

            HStack(spacing: 14) {
                tile(symbol: "shippingbox.fill", value: "\(library.items.count)",
                     caption: library.items.count == 1 ? "file in your library" : "files in your library") {
                    router.tab = .library
                }
                tile(symbol: "cube.transparent.fill", value: "Client",
                     caption: "Built-in AETHER features") {
                    router.tab = .client
                }
            }

            Text("AETHER opens the Minecraft you already have. It doesn't copy, patch or run Minecraft itself, because iOS doesn't allow that.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 4)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var accountChip: some View {
        HStack(spacing: 8) {
            Image(systemName: account.profile == nil ? "person.crop.circle" : "person.crop.circle.fill")
                .foregroundStyle(Theme.accent)
            Text(account.profile?.gamertag ?? "Sign in")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.graphite.opacity(0.7)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var versionCard: some View {
        Button {
            Haptics.tap()
            router.tab = .versions
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.stack.3d.up.fill").font(.title3).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(versions.active.map { "Minecraft \($0.versionName)" } ?? "No version recorded")
                        .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                    Text(versions.active == nil
                         ? "Add your installed version on the Versions tab"
                         : "Recorded by you. AETHER can't read the installed version.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            }
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private var recentDownloads: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent downloads").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                Spacer()
                NavigationLink("All") { DownloadsView() }
                    .font(.footnote.weight(.semibold))
            }
            ForEach(downloads.records.prefix(3)) { record in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: record.state)).foregroundStyle(color(for: record.state))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.projectName ?? record.fileName).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                        Text(label(for: record)).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                }
            }
        }
        .glassCard()
    }

    private func icon(for state: DownloadRecord.State) -> String {
        switch state {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        default: return "arrow.down.circle.fill"
        }
    }

    private func color(for state: DownloadRecord.State) -> Color {
        switch state {
        case .completed: return Theme.accent
        case .failed, .cancelled: return Theme.warning
        default: return .white
        }
    }

    private func label(for record: DownloadRecord) -> String {
        switch record.state {
        case .completed: return "In your library. Not yet sent to Minecraft."
        case .failed: return record.errorMessage ?? "Failed"
        case .cancelled: return "Cancelled"
        case .validating: return "Checking file"
        default: return "\(Int(record.progress * 100))%"
        }
    }

    private func tile(symbol: String, value: String, caption: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent)
                Text(value).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
                Text(caption).font(.caption).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.leading)
            }
            .glassCard(radius: 22, padding: 16)
        }
        .buttonStyle(.plain)
    }
}
