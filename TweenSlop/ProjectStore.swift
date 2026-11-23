import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    static var rootURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func folder(for id: UUID) -> URL {
        let url = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func assetsFolder(for id: UUID) -> URL {
        let url = folder(for: id).appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    init() {
        load()
    }

    func load() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Self.rootURL, includingPropertiesForKeys: nil)) ?? []
        var loaded: [Project] = []
        for dir in dirs {
            let file = dir.appendingPathComponent("project.json")
            if let data = try? Data(contentsOf: file), let p = try? JSONDecoder().decode(Project.self, from: data) {
                loaded.append(p)
            }
        }
        projects = loaded.sorted { $0.modified > $1.modified }
    }

    func create(name: String) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = Project(name: trimmed.isEmpty ? "Untitled" : trimmed)
        write(p)
        projects.insert(p, at: 0)
        return p
    }

    func write(_ p: Project) {
        let file = Self.folder(for: p.id).appendingPathComponent("project.json")
        if let data = try? JSONEncoder().encode(p) {
            try? data.write(to: file, options: .atomic)
        }
    }

    func commit(_ p: Project) {
        write(p)
        if let i = projects.firstIndex(where: { $0.id == p.id }) {
            projects[i] = p
        } else {
            projects.insert(p, at: 0)
        }
        projects.sort { $0.modified > $1.modified }
    }

    func delete(_ p: Project) {
        try? FileManager.default.removeItem(at: Self.folder(for: p.id))
        projects.removeAll { $0.id == p.id }
    }
}
