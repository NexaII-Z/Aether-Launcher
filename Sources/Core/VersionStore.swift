import SwiftUI

struct VersionRecord: Codable, Identifiable, Equatable {
    enum Source: String, Codable {
        case infoPlist = "Imported from Info.plist"
        case manual = "Entered manually"
    }

    let id: UUID
    var versionName: String
    var build: String?
    var bundleID: String
    var minimumOS: String?
    var source: Source
    var addedAt: Date
    var notes: String
}

struct RepairReport {
    let created: [String]
    var summary: String {
        created.isEmpty ? "Nothing needed repair." : "Recreated: \(created.joined(separator: ", "))."
    }
}

/// Version records are *metadata plus isolated AETHER storage*. They are not installations:
/// iOS only provides the current App Store build, and AETHER can't run any other executable.
final class VersionStore: ObservableObject {
    static let subfolders = ["worlds", "resource_packs", "behavior_packs", "config"]
    static let releaseNotesURL = URL(string: "https://feedback.minecraft.net/hc/en-us/sections/360001186971-Release-Changelogs")

    @Published private(set) var records: [VersionRecord] = []
    @Published var activeID: UUID? {
        didSet { UserDefaults.standard.set(activeID?.uuidString, forKey: "aether.activeVersion") }
    }
    @Published var lastError: String?

    private var fileURL: URL { AetherStorage.url(for: .settings).appendingPathComponent("versions.json") }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([VersionRecord].self, from: data) {
            records = decoded
        }
        if let stored = UserDefaults.standard.string(forKey: "aether.activeVersion"),
           let id = UUID(uuidString: stored), records.contains(where: { $0.id == id }) {
            activeID = id
        }
    }

    var active: VersionRecord? { records.first { $0.id == activeID } }

    func dataDirectory(for record: VersionRecord) -> URL {
        let directory = AetherStorage.url(for: .versions).appendingPathComponent(record.id.uuidString, isDirectory: true)
        for folder in Self.subfolders {
            try? FileManager.default.createDirectory(at: directory.appendingPathComponent(folder, isDirectory: true),
                                                     withIntermediateDirectories: true)
        }
        return directory
    }

    func addManual(version: String, build: String?, notes: String) {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { lastError = "Enter a version number, for example 1.26.32."; return }
        append(VersionRecord(id: UUID(), versionName: trimmed, build: build?.nilIfEmpty,
                             bundleID: "com.mojang.minecraftpe", minimumOS: nil,
                             source: .manual, addedAt: Date(), notes: notes))
    }

    /// Reads version metadata from a Minecraft Info.plist the user picked in Files.
    func addFromInfoPlist(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String else {
            lastError = "That file isn't a readable Info.plist with a CFBundleShortVersionString."
            return
        }
        let bundleID = plist["CFBundleIdentifier"] as? String ?? "unknown"
        append(VersionRecord(id: UUID(), versionName: version, build: plist["CFBundleVersion"] as? String,
                             bundleID: bundleID, minimumOS: plist["MinimumOSVersion"] as? String,
                             source: .infoPlist, addedAt: Date(), notes: ""))
    }

    private func append(_ record: VersionRecord) {
        records.insert(record, at: 0)
        if activeID == nil { activeID = record.id }
        _ = dataDirectory(for: record)
        persist()
    }

    func setNotes(_ notes: String, for record: VersionRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index].notes = notes
        persist()
    }

    /// Deletes only AETHER-managed data for this version, never anything inside Minecraft.
    func remove(_ record: VersionRecord) {
        let directory = AetherStorage.url(for: .versions).appendingPathComponent(record.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        records.removeAll { $0.id == record.id }
        if activeID == record.id { activeID = records.first?.id }
        persist()
    }

    func repair(_ record: VersionRecord) -> RepairReport {
        let base = AetherStorage.url(for: .versions).appendingPathComponent(record.id.uuidString, isDirectory: true)
        var created: [String] = []
        for folder in Self.subfolders {
            let path = base.appendingPathComponent(folder, isDirectory: true)
            if !FileManager.default.fileExists(atPath: path.path) {
                try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                created.append(folder)
            }
        }
        return RepairReport(created: created)
    }

    func usage(of record: VersionRecord) -> Int64 {
        AetherStorage.size(of: AetherStorage.url(for: .versions).appendingPathComponent(record.id.uuidString, isDirectory: true))
    }

    /// Real check against this device: does the device's iOS meet the recorded minimum?
    func compatibility(of record: VersionRecord) -> (compatible: Bool?, text: String) {
        let device = UIDevice.current.systemVersion
        guard let minimum = record.minimumOS else {
            return (nil, "Minimum iOS unknown. This device runs iOS \(device).")
        }
        let ok = device.compare(minimum, options: .numeric) != .orderedAscending
        return (ok, ok ? "Needs iOS \(minimum) or later. This device runs iOS \(device)."
                       : "Needs iOS \(minimum) or later, but this device runs iOS \(device).")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
