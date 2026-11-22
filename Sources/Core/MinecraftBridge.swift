import SwiftUI
import UIKit

enum MinecraftStatus: Equatable {
    case unknown
    case installed
    case notInstalled
}

enum LaunchResult: Equatable {
    case opened(Date)
    case failed(String)
}

/// Talks to the official Minecraft app through public iOS mechanisms only:
/// the `minecraft://` URL scheme (registered by the app) and its document types.
@MainActor
final class MinecraftBridge: ObservableObject {
    static let scheme = "minecraft"
    static let bundleIdentifier = "com.mojang.minecraftpe"
    static let launchURL = URL(string: "minecraft://")!
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id479516143")!

    @Published private(set) var status: MinecraftStatus = .unknown
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastLaunch: LaunchResult?

    func refresh() {
        status = UIApplication.shared.canOpenURL(Self.launchURL) ? .installed : .notInstalled
        lastChecked = Date()
    }

    @discardableResult
    func launch() async -> Bool {
        refresh()
        guard status == .installed else {
            lastLaunch = .failed("Minecraft isn't installed. Get the official app from the App Store first.")
            Haptics.failure()
            return false
        }
        let opened = await UIApplication.shared.open(Self.launchURL, options: [:])
        if opened {
            lastLaunch = .opened(Date())
            Haptics.success()
        } else {
            lastLaunch = .failed("iOS declined to open Minecraft. Open it once from the Home Screen, then try again.")
            Haptics.failure()
        }
        return opened
    }

    func openAppStore() async {
        _ = await UIApplication.shared.open(Self.appStoreURL, options: [:])
    }
}
