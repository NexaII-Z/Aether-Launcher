import SwiftUI

struct RootView: View {
    @EnvironmentObject private var bridge: MinecraftBridge
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.autoRefresh) private var autoRefresh = true

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            NavigationStack { PlayView() }
                .tabItem { Label("Play", systemImage: "play.fill") }
                .tag(AppTab.play)
            NavigationStack { PacksView() }
                .tabItem { Label("Packs", systemImage: "shippingbox.fill") }
                .tag(AppTab.packs)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(Theme.accent)
        .onChange(of: scenePhase) { phase in
            if phase == .active && autoRefresh { bridge.refresh() }
        }
    }
}
