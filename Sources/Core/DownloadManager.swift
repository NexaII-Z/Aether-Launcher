import Foundation
import CryptoKit
import UserNotifications

struct DownloadRecord: Codable, Identifiable, Equatable {
    enum State: String, Codable {
        case queued, downloading, validating, completed, failed, cancelled
    }

    let id: UUID
    var url: URL
    var fileName: String
    var projectName: String?
    var projectID: Int?
    var fileID: Int?
    var expectedSHA1: String?
    var expectedSize: Int64?
    var state: State
    var progress: Double
    var bytesWritten: Int64
    var totalBytes: Int64
    var errorMessage: String?
    var libraryFileName: String?
    var createdAt: Date
    var finishedAt: Date?

    var isActive: Bool { state == .queued || state == .downloading || state == .validating }
    var canRetry: Bool { state == .failed || state == .cancelled }
}

enum EnqueueResult {
    case started(UUID)
    case duplicate(String)
    case rejected(String)
}

private enum FinalizeOutcome {
    case success(libraryName: String, sha1: String)
    case duplicate(existing: String)
    case failure(String)
}

/// Validates and files a finished download. Runs off the main thread.
private enum DownloadFinalizer {
    static func run(staging: URL, fileName: String, expectedSHA1: String?,
                    libraryDirectory: URL, knownHashes: [String: String]) -> FinalizeOutcome {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let size = ((try? FileManager.default.attributesOfItem(atPath: staging.path))?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { return .failure("The server sent an empty file.") }
        guard DownloadManager.supportedExtensions.contains(ext) else {
            return .failure(".\(ext) isn't a supported Minecraft format.")
        }
        guard hasZipMagic(staging) else {
            return .failure("The file isn't a ZIP archive, so it can't be a Minecraft pack. The link may have returned a web page.")
        }
        guard let digest = try? sha1(of: staging) else { return .failure("Couldn't read the downloaded file.") }
        if let expected = expectedSHA1?.lowercased(), !expected.isEmpty, expected != digest {
            return .failure("Checksum mismatch. The file is damaged or was changed in transit.")
        }
        if let existing = knownHashes[digest], FileManager.default.fileExists(atPath: libraryDirectory.appendingPathComponent(existing).path) {
            return .duplicate(existing: existing)
        }

        var finalExt = ext
        if ext == "mcpack" || ext == "zip" {
            let inspection = PackInspector.inspect(url: staging, extension: "mcpack")
            guard inspection.hasManifest else { return .failure("The archive has no manifest.json, so Minecraft won't recognise it.") }
            finalExt = "mcpack"
        }

        let base = (fileName as NSString).deletingPathExtension
        let destination = LibraryIO.uniqueDestination(base: base, ext: finalExt, in: libraryDirectory)
        do {
            try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staging, to: destination)
            return .success(libraryName: destination.lastPathComponent, sha1: digest)
        } catch {
            return .failure("Couldn't save the file: \(error.localizedDescription)")
        }
    }

    static func hasZipMagic(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        return head[head.startIndex] == 0x50 && head[head.startIndex + 1] == 0x4B
    }

    static func sha1(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Real downloads with progress, cancel, retry, persistent history, duplicate detection and validation.
/// Limitation: it uses a foreground URLSession, so transfers pause while AETHER is suspended.
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let supportedExtensions: Set<String> = ["mcpack", "mcaddon", "mcworld", "mctemplate", "zip"]
    static let notifyKey = "aether.notifyDownloads"

    @Published private(set) var records: [DownloadRecord] = []

    private var session: URLSession!
    private var taskForRecord: [UUID: URLSessionDownloadTask] = [:]
    private var recordForTask: [Int: UUID] = [:]
    private weak var library: PackLibrary?
    private weak var meta: LibraryMetaStore?

    private var historyURL: URL { AetherStorage.url(for: .settings).appendingPathComponent("downloads.json") }

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)

        if let data = try? Data(contentsOf: historyURL),
           var decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            for index in decoded.indices where decoded[index].isActive {
                decoded[index].state = .failed
                decoded[index].errorMessage = "Interrupted when AETHER closed. Tap Retry."
            }
            records = decoded
        }
    }

    func attach(library: PackLibrary, meta: LibraryMetaStore) {
        self.library = library
        self.meta = meta
    }

    var activeCount: Int { records.filter(\.isActive).count }

    // MARK: Commands

    @discardableResult
    func enqueue(url: URL, fileName: String, projectName: String?, projectID: Int?, fileID: Int?,
                 sha1: String?, size: Int64?, allowDuplicate: Bool = false) -> EnqueueResult {
        guard url.scheme == "https" else { return .rejected("Only https downloads are allowed.") }
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            return .rejected("\(fileName) isn't a Minecraft format AETHER supports (.mcpack, .mcaddon, .mcworld, .mctemplate, .zip).")
        }
        if records.contains(where: { $0.url == url && $0.isActive }) { return .rejected("That file is already downloading.") }
        if !allowDuplicate, let existing = existingDuplicate(url: url, fileID: fileID, projectID: projectID) {
            return .duplicate(existing)
        }

        let record = DownloadRecord(id: UUID(), url: url, fileName: fileName, projectName: projectName,
                                    projectID: projectID, fileID: fileID, expectedSHA1: sha1, expectedSize: size,
                                    state: .queued, progress: 0, bytesWritten: 0, totalBytes: size ?? 0,
                                    errorMessage: nil, libraryFileName: nil, createdAt: Date(), finishedAt: nil)
        records.insert(record, at: 0)
        start(record.id)
        return .started(record.id)
    }

    func cancel(_ id: UUID) {
        taskForRecord[id]?.cancel()
    }

    func retry(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }), record.canRetry else { return }
        update(id) {
            $0.state = .queued; $0.progress = 0; $0.bytesWritten = 0
            $0.errorMessage = nil; $0.finishedAt = nil
        }
        start(id)
    }

    func remove(_ id: UUID) {
        taskForRecord[id]?.cancel()
        records.removeAll { $0.id == id }
        persist()
    }

    func clearFinished() {
        records.removeAll { !$0.isActive }
        persist()
    }

    // MARK: Internals

    private func existingDuplicate(url: URL, fileID: Int?, projectID: Int?) -> String? {
        for record in records where record.state == .completed {
            let sameFile = (fileID != nil && record.fileID == fileID && record.projectID == projectID) || record.url == url
            if sameFile, let name = record.libraryFileName,
               FileManager.default.fileExists(atPath: AetherStorage.libraryURL.appendingPathComponent(name).path) {
                return name
            }
        }
        return nil
    }

    private func start(_ id: UUID) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        var request = URLRequest(url: record.url)
        request.setValue("AETHER-Launcher/3.0", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        taskForRecord[id] = task
        recordForTask[task.taskIdentifier] = id
        update(id) { $0.state = .downloading }
        task.resume()
    }

    private func update(_ id: UUID, persist shouldPersist: Bool = true, _ change: (inout DownloadRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
        if shouldPersist { persist() }
    }

    private func fail(_ id: UUID, _ message: String) {
        update(id) { $0.state = .failed; $0.errorMessage = message; $0.finishedAt = Date() }
    }

    private func persist() {
        let trimmed = Array(records.prefix(200))
        if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    private func finalize(_ id: UUID, staging: URL) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        let fileName = record.fileName
        let expected = record.expectedSHA1
        let libraryDirectory = AetherStorage.libraryURL
        var known: [String: String] = [:]
        if let meta {
            for (name, entry) in meta.entries { if let hash = entry.sha1 { known[hash] = name } }
        }

        Task.detached(priority: .utility) { [weak self] in
            let outcome = DownloadFinalizer.run(staging: staging, fileName: fileName, expectedSHA1: expected,
                                                libraryDirectory: libraryDirectory, knownHashes: known)
            DispatchQueue.main.async { self?.apply(outcome, to: id, staging: staging) }
        }
    }

    private func apply(_ outcome: FinalizeOutcome, to id: UUID, staging: URL) {
        switch outcome {
        case .success(let name, let digest):
            let record = records.first(where: { $0.id == id })
            update(id) {
                $0.state = .completed; $0.progress = 1; $0.libraryFileName = name
                $0.errorMessage = nil; $0.finishedAt = Date()
            }
            meta?.update(name) {
                $0.origin = .downloaded
                $0.sourceProject = record?.projectName
                $0.sourceURL = record?.url.absoluteString
                $0.sha1 = digest
            }
            Task { await library?.reload() }
            notify(title: "Download finished", body: record?.projectName ?? name)
        case .duplicate(let existing):
            try? FileManager.default.removeItem(at: staging)
            update(id) {
                $0.state = .completed; $0.progress = 1; $0.libraryFileName = existing
                $0.errorMessage = "Identical to \(existing), which is already in your library."
                $0.finishedAt = Date()
            }
        case .failure(let message):
            try? FileManager.default.removeItem(at: staging)
            fail(id, message)
        }
    }

    private func notify(title: String, body: String) {
        guard UserDefaults.standard.bool(forKey: Self.notifyKey) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: URLSessionDownloadDelegate (delivered on the main queue)

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = recordForTask[downloadTask.taskIdentifier] else { return }
        update(id, persist: false) {
            $0.bytesWritten = totalBytesWritten
            $0.totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : $0.totalBytes
            $0.progress = $0.totalBytes > 0 ? min(1, Double(totalBytesWritten) / Double($0.totalBytes)) : 0
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = recordForTask[downloadTask.taskIdentifier] else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            fail(id, "The server answered HTTP \(http.statusCode).")
            return
        }
        let staging = AetherStorage.url(for: .downloads).appendingPathComponent("\(id.uuidString).part")
        try? FileManager.default.removeItem(at: staging)
        do {
            try FileManager.default.moveItem(at: location, to: staging)
        } catch {
            fail(id, "Couldn't stage the download: \(error.localizedDescription)")
            return
        }
        update(id) { $0.state = .validating; $0.progress = 1 }
        finalize(id, staging: staging)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = recordForTask.removeValue(forKey: task.taskIdentifier) else { return }
        taskForRecord[id] = nil
        guard let error else { return }
        if (error as NSError).code == NSURLErrorCancelled {
            update(id) { $0.state = .cancelled; $0.finishedAt = Date() }
        } else {
            fail(id, error.localizedDescription)
        }
    }
}
