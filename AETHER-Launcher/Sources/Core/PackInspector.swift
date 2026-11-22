import Foundation

struct PackInspection: Equatable, Sendable {
    var displayName: String?
    var version: String?
    var contents: [String] = []
    var hasManifest = false
}

/// Minimal read-only ZIP reader. It only reads the central directory and a few
/// small entries (manifest.json / levelname.txt) to label imported files.
enum PackInspector {
    private struct Entry {
        let name: String
        let method: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localOffset: Int
    }

    private static let maxEntryBytes = 1_048_576

    static func inspect(url: URL, extension ext: String) -> PackInspection {
        var result = PackInspection()
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let entries = readDirectory(data) else { return result }

        if ext == "mcworld" {
            if let entry = entries.first(where: { $0.name == "levelname.txt" }),
               let bytes = read(entry, from: data),
               let text = String(data: bytes, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.displayName = trimmed }
            }
            return result
        }

        let candidates = entries.filter {
            !$0.name.hasPrefix("__MACOSX") && ($0.name == "manifest.json" || $0.name.hasSuffix("/manifest.json"))
        }
        guard let manifest = candidates.min(by: { $0.name.count < $1.name.count }) else { return result }
        result.hasManifest = true

        guard let bytes = read(manifest, from: data),
              let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return result }

        if let header = json["header"] as? [String: Any] {
            if let name = header["name"] as? String, !name.isEmpty, !name.hasPrefix("pack.") {
                result.displayName = name
            }
            if let parts = header["version"] as? [Int] {
                result.version = parts.map(String.init).joined(separator: ".")
            } else if let text = header["version"] as? String {
                result.version = text
            }
        }

        if let modules = json["modules"] as? [[String: Any]] {
            var seen = Set<String>()
            result.contents = modules
                .compactMap { $0["type"] as? String }
                .map(label(forModuleType:))
                .filter { seen.insert($0).inserted }
        }
        return result
    }

    private static func label(forModuleType type: String) -> String {
        switch type.lowercased() {
        case "resources": return "Resource pack"
        case "data": return "Behavior pack"
        case "script": return "Scripts"
        case "skin_pack": return "Skin pack"
        case "world_template": return "World template"
        case "client_data": return "Client data"
        case "interface": return "UI"
        default: return type.capitalized
        }
    }

    private static func readDirectory(_ data: Data) -> [Entry]? {
        let total = data.count
        guard total >= 22 else { return nil }

        let lowest = max(0, total - 22 - 65_535)
        var cursor = total - 22
        var eocd = -1
        while cursor >= lowest {
            if data.u32(cursor) == 0x06054b50 { eocd = cursor; break }
            cursor -= 1
        }
        guard eocd >= 0 else { return nil }

        let count = data.u16(eocd + 10)
        let directorySize = data.u32(eocd + 12)
        let directoryOffset = data.u32(eocd + 16)
        guard directoryOffset != 0xFFFF_FFFF, directoryOffset + directorySize <= total else { return nil }

        var entries: [Entry] = []
        var position = directoryOffset
        for _ in 0..<count {
            guard position + 46 <= total, data.u32(position) == 0x02014b50 else { break }
            let method = data.u16(position + 10)
            let compressed = data.u32(position + 20)
            let uncompressed = data.u32(position + 24)
            let nameLength = data.u16(position + 28)
            let extraLength = data.u16(position + 30)
            let commentLength = data.u16(position + 32)
            let localOffset = data.u32(position + 42)
            guard position + 46 + nameLength <= total else { break }

            let start = data.startIndex + position + 46
            let nameBytes = data.subdata(in: start..<(start + nameLength))
            entries.append(Entry(name: String(decoding: nameBytes, as: UTF8.self),
                                 method: method,
                                 compressedSize: compressed,
                                 uncompressedSize: uncompressed,
                                 localOffset: localOffset))
            position += 46 + nameLength + extraLength + commentLength
        }
        return entries.isEmpty ? nil : entries
    }

    private static func read(_ entry: Entry, from data: Data) -> Data? {
        guard entry.compressedSize <= maxEntryBytes, entry.uncompressedSize <= maxEntryBytes else { return nil }
        guard entry.localOffset + 30 <= data.count, data.u32(entry.localOffset) == 0x04034b50 else { return nil }

        let dataStart = entry.localOffset + 30 + data.u16(entry.localOffset + 26) + data.u16(entry.localOffset + 28)
        guard dataStart + entry.compressedSize <= data.count else { return nil }

        let from = data.startIndex + dataStart
        let raw = data.subdata(in: from..<(from + entry.compressedSize))

        switch entry.method {
        case 0:
            return raw
        case 8:
            guard let inflated = try? (raw as NSData).decompressed(using: .zlib) else { return nil }
            return inflated as Data
        default:
            return nil
        }
    }
}

private extension Data {
    func u16(_ offset: Int) -> Int {
        let base = startIndex + offset
        return Int(self[base]) | (Int(self[base + 1]) << 8)
    }

    func u32(_ offset: Int) -> Int {
        return u16(offset) | (u16(offset + 2) << 16)
    }
}
