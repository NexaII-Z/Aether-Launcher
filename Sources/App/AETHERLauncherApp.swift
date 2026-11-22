import SwiftUI

enum AppTab: Hashable {
    case home, play, packs, settings
}

final class Router: ObservableObject {
    @Published var tab: AppTab = .home
}

@main
struct AETHERLauncherApp: App {
    @StateObject private var bridge = MinecraftBridge()
    @StateObject private var library = PackLibrary()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(bridge)
                .environmentObject(library)
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .task {
                    bridge.refresh()
                    await library.reload()
                }
        }
    }
}
