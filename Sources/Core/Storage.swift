import Foundation

enum StorageBucket: String, CaseIterable, Identifiable {
    case versions, downloads, worlds, resourcePacks, behaviorPacks, settings, cache, clients

    var id: String { rawValue }

    var title: String {
        switch self {
        case .versions: return "Version metadata"
        case .downloads: return "Download staging"
        case .worlds: return "Worlds"
        case .resourcePacks: return "Resource packs"
        case .behaviorPacks: return "Behavior packs"
        case .settings: return "Settings and history"
        case .cache: return "Cache"
        case .clients: return "Client configurations"
        }
    }

    var symbol: String {
        switch self {
        case .versions: return "square.stack.3d.up.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .worlds: return "globe.europe.africa.fill"
        case .resourcePacks: return "paintpalette.fill"
        case .behaviorPacks: return "gearshape.2.fill"
        case .settings: return "slider.horizontal.3"
        case .cache: return "internaldrive.fill"
        case .clients: return "cube.transparent.fill"
        }
    }

    var directoryName: String {
        switch self {
        case .versions: return "Versions"
        case .downloads: return "Downloads"
        case .worlds: return "Worlds"
        case .resourcePacks: return "ResourcePacks"
        case .behaviorPacks: return "BehaviorPacks"
        case .settings: return "Settings"
        case .cache: return "Cache"
        case .clients: return "Clients"
        }
    }

    /// Buckets the user can safely empty without losing their own content.
    var isClearable: Bool { self == .cache || self == .downloads }
}

/// AETHER's own storage. Everything lives in AETHER's sandbox; nothing here touches
/// Minecraft's container. The user-visible import library stays in Documents so it
/// appears in the Files app (unchanged from AETHER 1.0).
enum AetherStorage {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AETHER", isDirectory: true)
    }

    static var libraryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AETHER Library", isDirectory: true)
    }

    static func url(for bucket: StorageBucket) -> URL {
        let url = root.appendingPathComponent(bucket.directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func bootstrap() {
        for bucket in StorageBucket.allCases { _ = url(for: bucket) }
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
    }

    static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    static func clear(_ bucket: StorageBucket) {
        let directory = url(for: bucket)
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for item in items { try? FileManager.default.removeItem(at: item) }
    }
}
