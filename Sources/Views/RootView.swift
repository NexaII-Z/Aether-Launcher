import SwiftUI

struct RootView: View {
    @EnvironmentObject private var bridge: MinecraftBridge
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.autoRefresh) private var autoRefresh = true

    var body: some View {
        ZStack {
            switch router.tab {
            case .home: NavigationStack { HomeView() }
            case .versions: NavigationStack { VersionsView() }
            case .client: NavigationStack { ClientView() }
            case .discover: NavigationStack { DiscoverView() }
            case .library: NavigationStack { LibraryView() }
            case .settings: NavigationStack { SettingsView() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { AetherTabBar() }
        .tint(Theme.accent)
        .onChange(of: scenePhase) { phase in
            if phase == .active && autoRefresh { bridge.refresh() }
        }
    }
}

struct AetherTabBar: View {
    @EnvironmentObject private var router: Router

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    Haptics.tap()
                    router.tab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 19, weight: .semibold))
                        Text(tab.title).font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(router.tab == tab ? Theme.accent : Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(router.tab == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
