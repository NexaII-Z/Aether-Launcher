import Foundation

struct LibraryMetaEntry: Codable, Equatable {
    enum Origin: String, Codable { case imported, downloaded }

    var origin: Origin = .imported
    var displayName: String?
    var favorite = false
    var sourceProject: String?
    var sourceURL: String?
    var sha1: String?
    var addedAt = Date()
    var lastHandedToMinecraft: Date?
}

/// Sidecar metadata for library files (rename, favourites, origin). File names on disk are untouched.
final class LibraryMetaStore: ObservableObject {
    @Published private(set) var entries: [String: LibraryMetaEntry] = [:]

    private var fileURL: URL { AetherStorage.url(for: .settings).appendingPathComponent("library-meta.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: LibraryMetaEntry].self, from: data) {
            entries = decoded
        }
    }

    func entry(for id: String) -> LibraryMetaEntry { entries[id] ?? LibraryMetaEntry() }

    func update(_ id: String, _ change: (inout LibraryMetaEntry) -> Void) {
        var entry = entries[id] ?? LibraryMetaEntry()
        change(&entry)
        entries[id] = entry
        persist()
    }

    func remove(_ id: String) {
        entries[id] = nil
        persist()
    }

    func prune(keeping ids: Set<String>) {
        let stale = entries.keys.filter { !ids.contains($0) }
        guard !stale.isEmpty else { return }
        for key in stale { entries[key] = nil }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
