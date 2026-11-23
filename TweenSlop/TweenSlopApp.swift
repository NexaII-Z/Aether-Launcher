import SwiftUI

@main
struct TweenSlopApp: App {
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(.red)
        }
    }
}
