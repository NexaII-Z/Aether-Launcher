import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home, versions, client, discover, library, settings

    var title: String {
        switch self {
        case .home: return "Home"
        case .versions: return "Versions"
        case .client: return "Client"
        case .discover: return "Discover"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .versions: return "square.stack.3d.up.fill"
        case .client: return "cube.transparent.fill"
        case .discover: return "magnifyingglass"
        case .library: return "shippingbox.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

final class Router: ObservableObject {
    @Published var tab: AppTab = .home
}

@main
struct AETHERLauncherApp: App {
    @StateObject private var bridge = MinecraftBridge()
    @StateObject private var library = PackLibrary()
    @StateObject private var router = Router()
    @StateObject private var features = FeatureManager()
    @StateObject private var versions = VersionStore()
    @StateObject private var meta = LibraryMetaStore()
    @StateObject private var downloads = DownloadManager()
    @StateObject private var account = AccountManager()
    @StateObject private var zoom = ZoomController()

    init() {
        AetherStorage.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(bridge)
                .environmentObject(library)
                .environmentObject(router)
                .environmentObject(features)
                .environmentObject(versions)
                .environmentObject(meta)
                .environmentObject(downloads)
                .environmentObject(account)
                .environmentObject(zoom)
                .preferredColorScheme(.dark)
                .task {
                    downloads.attach(library: library, meta: meta)
                    bridge.refresh()
                    await library.reload()
                    meta.prune(keeping: Set(library.items.map(\.id)))
                }
        }
    }
}
