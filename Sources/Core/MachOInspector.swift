import Foundation

struct MachOLibrary: Identifiable, Equatable, Sendable {
    var id: String { kind + name }
    let kind: String
    let name: String
}

struct MachOReport: Sendable {
    var fileName: String
    var fileSize: Int64
    var architecture = "unknown"
    var fileType = "unknown"
    var isPIE = false
    var platform: String?
    var minOS: String?
    var sdk: String?
    var cryptID: Int?
    var hasCodeSignature = false
    var signingIdentifier: String?
    var teamID: String?
    var entitlements: [String: String] = [:]
    var libraries: [MachOLibrary] = []
    var rpaths: [String] = []

    var isExecutable: Bool { fileType == "EXECUTE" }

    var text: String {
        var lines = ["AETHER runtime investigation: \(fileName)",
                     "Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))",
                     "Architecture: \(architecture)   Type: \(fileType)   PIE: \(isPIE ? "yes" : "no")"]
        if let platform { lines.append("Platform: \(platform)   Minimum OS: \(minOS ?? "?")   SDK: \(sdk ?? "?")") }
        if let cryptID { lines.append("FairPlay cryptid: \(cryptID)") }
        lines.append("Code signature: \(hasCodeSignature ? "present" : "absent")")
        if let signingIdentifier { lines.append("Signing identifier: \(signingIdentifier)") }
        if let teamID { lines.append("Team ID: \(teamID)") }
        for (key, value) in entitlements.sorted(by: { $0.key < $1.key }) { lines.append("Entitlement \(key) = \(value)") }
        for rpath in rpaths { lines.append("rpath: \(rpath)") }
        for library in libraries { lines.append("\(library.kind): \(library.name)") }
        return lines.joined(separator: "\n")
    }
}

enum MachOError: LocalizedError {
    case unreadable
    case notMachO
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "The file couldn't be read."
        case .notMachO: return "This isn't a Mach-O binary."
        case .unsupported(let why): return why
        }
    }
}

/// Read-only static inspector. It never loads, executes or modifies the file.
enum MachOInspector {
    private static let headBytes = 8 * 1024 * 1024
    private static let maxSignatureBytes = 16 * 1024 * 1024

    static func inspect(url: URL) throws -> MachOReport {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let handle = try? FileHandle(forReadingFrom: url) else { throw MachOError.unreadable }
        defer { try? handle.close() }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        var report = MachOReport(fileName: url.lastPathComponent, fileSize: size)

        var base: UInt64 = 0
        guard var head = try? handle.read(upToCount: headBytes), head.count >= 32 else { throw MachOError.notMachO }

        if head.be32(0) == 0xCAFEBABE {
            let count = Int(head.be32(4))
            var chosen: (cpu: UInt32, offset: UInt32)?
            for index in 0..<min(count, 8) {
                let entry = 8 + index * 20
                guard entry + 20 <= head.count else { break }
                let cpu = head.be32(entry), offset = head.be32(entry + 8)
                if chosen == nil || cpu == 0x0100000C { chosen = (cpu, offset) }
            }
            guard let slice = chosen else { throw MachOError.notMachO }
            base = UInt64(slice.offset)
            try handle.seek(toOffset: base)
            guard let sliced = try handle.read(upToCount: headBytes), sliced.count >= 32 else { throw MachOError.notMachO }
            head = sliced
        }

        guard head.le32(0) == 0xFEEDFACF else {
            if head.le32(0) == 0xFEEDFACE { throw MachOError.unsupported("32-bit Mach-O files aren't supported.") }
            throw MachOError.notMachO
        }

        let cpu = head.le32(4)
        let fileType = head.le32(12)
        let commandCount = Int(head.le32(16))
        let flags = head.le32(24)

        report.architecture = cpu == 0x0100000C ? "arm64" : (cpu == 0x01000007 ? "x86_64" : String(format: "0x%X", cpu))
        report.fileType = ["1": "OBJECT", "2": "EXECUTE", "6": "DYLIB", "8": "BUNDLE"][String(fileType)] ?? String(fileType)
        report.isPIE = flags & 0x200000 != 0

        var offset = 32
        var signature: (offset: UInt32, size: UInt32)?
        for _ in 0..<commandCount {
            guard offset + 8 <= head.count else { break }
            let command = head.le32(offset)
            let length = Int(head.le32(offset + 4))
            guard length >= 8, offset + length <= head.count else { break }

            switch command {
            case 0xC, 0x80000018, 0x8000001F, 0xD:
                let kinds: [UInt32: String] = [0xC: "LOAD_DYLIB", 0x80000018: "LOAD_WEAK_DYLIB",
                                               0x8000001F: "REEXPORT_DYLIB", 0xD: "ID_DYLIB"]
                let nameOffset = Int(head.le32(offset + 8))
                report.libraries.append(MachOLibrary(kind: kinds[command] ?? "DYLIB",
                                                     name: head.cString(from: offset + nameOffset, limit: offset + length)))
            case 0x8000001C:
                let nameOffset = Int(head.le32(offset + 8))
                report.rpaths.append(head.cString(from: offset + nameOffset, limit: offset + length))
            case 0x1D:
                signature = (head.le32(offset + 8), head.le32(offset + 12))
            case 0x2C:
                report.cryptID = Int(head.le32(offset + 16))
            case 0x32:
                let platforms: [UInt32: String] = [1: "macOS", 2: "iOS", 3: "tvOS", 4: "watchOS", 7: "iOS Simulator"]
                let platform = head.le32(offset + 8)
                report.platform = platforms[platform] ?? String(platform)
                report.minOS = version(head.le32(offset + 12))
                report.sdk = version(head.le32(offset + 16))
            default:
                break
            }
            offset += length
        }

        if let signature, signature.size > 0, signature.size <= maxSignatureBytes {
            report.hasCodeSignature = true
            try handle.seek(toOffset: base + UInt64(signature.offset))
            if let blob = try handle.read(upToCount: Int(signature.size)) {
                parseSignature(blob, into: &report)
            }
        }
        return report
    }

    private static func version(_ packed: UInt32) -> String {
        "\(packed >> 16).\((packed >> 8) & 0xFF)"
    }

    private static func parseSignature(_ blob: Data, into report: inout MachOReport) {
        guard blob.count >= 12, blob.be32(0) == 0xFADE0CC0 else { return }
        let count = Int(blob.be32(8))
        for index in 0..<min(count, 32) {
            let entry = 12 + index * 8
            guard entry + 8 <= blob.count else { break }
            let offset = Int(blob.be32(entry + 4))
            guard offset + 8 <= blob.count else { continue }
            let magic = blob.be32(offset)
            let length = Int(blob.be32(offset + 4))

            if magic == 0xFADE0C02, report.signingIdentifier == nil, offset + 52 <= blob.count {
                let identOffset = Int(blob.be32(offset + 20))
                report.signingIdentifier = blob.cString(from: offset + identOffset, limit: min(blob.count, offset + length))
                if blob.be32(offset + 8) >= 0x20200 {
                    let teamOffset = Int(blob.be32(offset + 48))
                    if teamOffset > 0 {
                        report.teamID = blob.cString(from: offset + teamOffset, limit: min(blob.count, offset + length))
                    }
                }
            } else if magic == 0xFADE7171, length > 8, offset + length <= blob.count {
                let plist = blob.subdata(in: (blob.startIndex + offset + 8)..<(blob.startIndex + offset + length))
                if let object = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil) as? [String: Any] {
                    for (key, value) in object { report.entitlements[key] = String(describing: value) }
                }
            }
        }
    }
}

private extension Data {
    func le32(_ offset: Int) -> UInt32 {
        let base = startIndex + offset
        guard offset >= 0, base + 4 <= endIndex else { return 0 }
        return UInt32(self[base]) | UInt32(self[base + 1]) << 8 | UInt32(self[base + 2]) << 16 | UInt32(self[base + 3]) << 24
    }

    func be32(_ offset: Int) -> UInt32 {
        let base = startIndex + offset
        guard offset >= 0, base + 4 <= endIndex else { return 0 }
        return UInt32(self[base]) << 24 | UInt32(self[base + 1]) << 16 | UInt32(self[base + 2]) << 8 | UInt32(self[base + 3])
    }

    func cString(from offset: Int, limit: Int) -> String {
        let start = startIndex + offset
        let end = Swift.min(startIndex + limit, endIndex)
        guard start >= startIndex, start < end else { return "" }
        let slice = self[start..<end]
        let bytes = slice.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}
