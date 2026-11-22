import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: PackLibrary
    @EnvironmentObject private var router: Router

    var body: some View {
        Screen {
            ScreenHeader(title: "AETHER", subtitle: "A launcher for the official Minecraft Bedrock app")

            NavigationLink {
                InstallStatusView()
            } label: {
                StatusCard()
            }
            .buttonStyle(.plain)

            LaunchButton()

            HStack(spacing: 14) {
                tile(symbol: "shippingbox.fill",
                     value: "\(library.items.count)",
                     caption: library.items.count == 1 ? "file in your library" : "files in your library") {
                    router.tab = .packs
                }
                tile(symbol: "gearshape.fill", value: "Settings", caption: "Launch and haptics options") {
                    router.tab = .settings
                }
            }

            Text("AETHER never copies, patches or replaces Minecraft. It opens the app you already have and hands it your pack files.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 4)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func tile(symbol: String, value: String, caption: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent)
                Text(value).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
                Text(caption).font(.caption).foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            .glassCard(radius: 22, padding: 16)
        }
        .buttonStyle(.plain)
    }
}
