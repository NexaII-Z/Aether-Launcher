import Foundation

// MARK: - Models (official CurseForge API v1; unknown fields are ignored)

struct CFPagination: Decodable {
    let index: Int?
    let pageSize: Int?
    let resultCount: Int?
    let totalCount: Int?
}

struct CFPage<T: Decodable>: Decodable {
    let data: [T]
    let pagination: CFPagination?
}

struct CFSingle<T: Decodable>: Decodable {
    let data: T
}

struct CFGame: Decodable, Identifiable {
    let id: Int
    let name: String
    let slug: String?
}

struct CFCategory: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String?
    let isClass: Bool?
    let classId: Int?
    let iconUrl: String?
}

struct CFAsset: Decodable, Hashable {
    let title: String?
    let thumbnailUrl: String?
    let url: String?
}

struct CFAuthor: Decodable, Hashable {
    let name: String
}

struct CFHash: Decodable, Hashable {
    let value: String
    let algo: Int
}

struct CFLinks: Decodable, Hashable {
    let websiteUrl: String?
}

struct CFFile: Decodable, Identifiable, Hashable {
    let id: Int
    let modId: Int?
    let displayName: String
    let fileName: String
    let downloadUrl: String?
    let fileLength: Int64?
    let releaseType: Int?
    let gameVersions: [String]?
    let fileDate: String?
    let hashes: [CFHash]?

    var sha1: String? { hashes?.first { $0.algo == 1 }?.value }

    var releaseLabel: String {
        switch releaseType {
        case 1: return "Release"
        case 2: return "Beta"
        case 3: return "Alpha"
        default: return "File"
        }
    }
}

struct CFMod: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String?
    let summary: String?
    let downloadCount: Double?
    let logo: CFAsset?
    let screenshots: [CFAsset]?
    let authors: [CFAuthor]?
    let links: CFLinks?
    let categories: [CFCategory]?
    let dateModified: String?
    let latestFiles: [CFFile]?
    let allowModDistribution: Bool?
    let classId: Int?
}

enum CFSort: Int, CaseIterable, Identifiable {
    case popularity = 2
    case totalDownloads = 6
    case lastUpdated = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .popularity: return "Popularity"
        case .totalDownloads: return "Downloads"
        case .lastUpdated: return "Latest update"
        }
    }
}

// MARK: - Client

enum CurseForgeError: LocalizedError {
    case notConfigured
    case http(Int)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your CurseForge API key (or a proxy address) in Settings, Discover."
        case .http(let code):
            switch code {
            case 401, 403: return "CurseForge rejected the API key (HTTP \(code)). Check the key in Settings."
            case 429: return "CurseForge is rate limiting requests. Wait a moment and try again."
            default: return "CurseForge answered HTTP \(code)."
            }
        case .unreadable(let detail):
            return "CurseForge sent a response AETHER couldn't read (\(detail))."
        }
    }
}

/// Talks to the official CurseForge API. AETHER ships **no** API key:
/// each user supplies their own (stored in the Keychain), or points AETHER at a proxy
/// that holds the key server-side.
struct CurseForgeClient {
    static let keychainKey = "curseforge.apikey"
    static let proxyKey = "curseforge.proxy"
    static let officialBase = URL(string: "https://api.curseforge.com")!

    let apiKey: String?
    let baseURL: URL

    static func fromSettings() -> CurseForgeClient? {
        let key = Keychain.get(keychainKey)?.nilIfEmpty
        let proxy = UserDefaults.standard.string(forKey: proxyKey)?.nilIfEmpty.flatMap { URL(string: $0) }
        guard key != nil || proxy != nil else { return nil }
        return CurseForgeClient(apiKey: key, baseURL: proxy ?? officialBase)
    }

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/" + path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw CurseForgeError.unreadable("bad URL") }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CurseForgeError.http(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CurseForgeError.unreadable(String(describing: error).prefix(120).description)
        }
    }

    func games() async throws -> [CFGame] {
        let page: CFPage<CFGame> = try await get("games")
        return page.data
    }

    func categories(gameID: Int) async throws -> [CFCategory] {
        let page: CFPage<CFCategory> = try await get("categories", [URLQueryItem(name: "gameId", value: String(gameID))])
        return page.data
    }

    func search(gameID: Int, classID: Int?, text: String, sort: CFSort, version: String,
                index: Int, pageSize: Int = 20) async throws -> CFPage<CFMod> {
        var query = [URLQueryItem(name: "gameId", value: String(gameID)),
                     URLQueryItem(name: "sortField", value: String(sort.rawValue)),
                     URLQueryItem(name: "sortOrder", value: "desc"),
                     URLQueryItem(name: "index", value: String(index)),
                     URLQueryItem(name: "pageSize", value: String(pageSize))]
        if let classID { query.append(URLQueryItem(name: "classId", value: String(classID))) }
        if let text = text.nilIfEmpty { query.append(URLQueryItem(name: "searchFilter", value: text)) }
        if let version = version.nilIfEmpty { query.append(URLQueryItem(name: "gameVersion", value: version)) }
        return try await get("mods/search", query)
    }

    func mod(id: Int) async throws -> CFMod {
        let single: CFSingle<CFMod> = try await get("mods/\(id)")
        return single.data
    }

    func description(modID: Int) async throws -> String {
        let single: CFSingle<String> = try await get("mods/\(modID)/description")
        return single.data
    }

    func files(modID: Int, gameVersion: String?) async throws -> [CFFile] {
        var query = [URLQueryItem(name: "pageSize", value: "30")]
        if let gameVersion = gameVersion?.nilIfEmpty { query.append(URLQueryItem(name: "gameVersion", value: gameVersion)) }
        let page: CFPage<CFFile> = try await get("mods/\(modID)/files", query)
        return page.data
    }

    func changelog(modID: Int, fileID: Int) async throws -> String {
        let single: CFSingle<String> = try await get("mods/\(modID)/files/\(fileID)/changelog")
        return single.data
    }

    func downloadURL(modID: Int, fileID: Int) async throws -> URL? {
        let single: CFSingle<String?> = try await get("mods/\(modID)/files/\(fileID)/download-url")
        return single.data.flatMap { URL(string: $0) }
    }
}

enum HTMLText {
    /// Small, dependency-free HTML to plain text conversion for CurseForge descriptions and changelogs.
    static func plain(from html: String) -> String {
        var text = html
        let breaks = ["</p>", "</div>", "</li>", "</h1>", "</h2>", "</h3>", "<br>", "<br/>", "<br />"]
        for tag in breaks { text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive) }
        text = text.replacingOccurrences(of: "<li>", with: "- ", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " ", "&apos;": "'"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
