import SwiftUI

enum PackKind: String, CaseIterable, Sendable {
    case mcpack, mcaddon, mcworld, mctemplate

    var title: String {
        switch self {
        case .mcpack: return "Pack"
        case .mcaddon: return "Add-on"
        case .mcworld: return "World"
        case .mctemplate: return "World template"
        }
    }

    var symbol: String {
        switch self {
        case .mcpack: return "paintpalette.fill"
        case .mcaddon: return "puzzlepiece.extension.fill"
        case .mcworld: return "globe.europe.africa.fill"
        case .mctemplate: return "square.on.square"
        }
    }
}

struct PackItem: Identifiable, Equatable, Sendable {
    var id: String { url.lastPathComponent }
    let url: URL
    let kind: PackKind
    let title: String
    let version: String?
    let contents: [String]
    let size: Int64
    let modified: Date

    var subtitle: String {
        var parts: [String] = []
        parts.append(contents.isEmpty ? kind.title : contents.joined(separator: ", "))
        if let version { parts.append("v\(version)") }
        parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        return parts.joined(separator: "  |  ")
    }
}

struct ImportReport: Sendable {
    var imported: [String] = []
    var failures: [String] = []
}

enum LibraryIO {
    static func scan(directory: URL) -> [PackItem] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [PackItem] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard let kind = PackKind(rawValue: ext) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let inspection = PackInspector.inspect(url: url, extension: ext)
            items.append(PackItem(
                url: url,
                kind: kind,
                title: inspection.displayName ?? url.deletingPathExtension().lastPathComponent,
                version: inspection.version,
                contents: inspection.contents,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? .distantPast
            ))
        }
        return items.sorted { $0.modified > $1.modified }
    }

    static func importFiles(_ urls: [URL], into directory: URL) -> ImportReport {
        var report = ImportReport()
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        for source in urls {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }

            let name = source.lastPathComponent
            let ext = source.pathExtension.lowercased()
            var targetExt = ext

            if ext == "zip" {
                let inspection = PackInspector.inspect(url: source, extension: "mcpack")
                guard inspection.hasManifest else {
                    report.failures.append("\(name): no manifest.json inside, so it isn't a Minecraft pack.")
                    continue
                }
                targetExt = "mcpack"
            } else if PackKind(rawValue: ext) == nil {
                report.failures.append("\(name): .\(ext) files aren't supported. Use .mcpack, .mcaddon, .mcworld, .mctemplate or a pack .zip.")
                continue
            }

            let destination = uniqueDestination(base: source.deletingPathExtension().lastPathComponent,
                                                ext: targetExt, in: directory)
            do {
                try fm.copyItem(at: source, to: destination)
                report.imported.append(destination.lastPathComponent)
            } catch {
                report.failures.append("\(name): \(error.localizedDescription)")
            }
        }
        return report
    }

    static func remove(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    static func uniqueDestination(base: String, ext: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }
}

struct LibraryBanner: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}

@MainActor
final class PackLibrary: ObservableObject {
    static let supportedExtensions = ["mcpack", "mcaddon", "mcworld", "mctemplate", "zip"]

    @Published private(set) var items: [PackItem] = []
    @Published private(set) var isWorking = false
    @Published var banner: LibraryBanner?

    let directory: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("AETHER Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func reload() async {
        let dir = directory
        items = await Task.detached(priority: .userInitiated) { LibraryIO.scan(directory: dir) }.value
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isWorking = true
        let dir = directory
        let report = await Task.detached(priority: .userInitiated) {
            LibraryIO.importFiles(urls, into: dir)
        }.value
        await reload()
        isWorking = false

        if report.failures.isEmpty {
            banner = LibraryBanner(message: "Imported \(report.imported.count) file\(report.imported.count == 1 ? "" : "s").",
                                   isError: false)
            Haptics.success()
        } else {
            var lines = report.failures
            if !report.imported.isEmpty { lines.insert("Imported \(report.imported.count) file(s).", at: 0) }
            banner = LibraryBanner(message: lines.joined(separator: "\n"), isError: true)
            Haptics.failure()
        }
    }

    func report(error message: String) {
        banner = LibraryBanner(message: message, isError: true)
        Haptics.failure()
    }

    func remove(_ item: PackItem) async {
        let target = item.url
        await Task.detached { LibraryIO.remove([target]) }.value
        await reload()
    }

    func removeAll() async {
        let targets = items.map(\.url)
        await Task.detached { LibraryIO.remove(targets) }.value
        await reload()
    }

    var filesAppURL: URL? {
        URL(string: directory.absoluteString.replacingOccurrences(of: "file://", with: "shareddocuments://"))
    }
}
