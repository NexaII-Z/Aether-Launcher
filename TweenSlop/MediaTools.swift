import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

enum MediaError: LocalizedError {
    case noAudio
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudio: return "That file has no audio track."
        case .exportFailed(let m): return "Audio export failed: \(m)"
        }
    }
}

enum MediaTools {
    static func extractAudio(from source: URL, to dest: URL) async throws {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw MediaError.noAudio }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaError.exportFailed("Could not create export session.")
        }
        try? FileManager.default.removeItem(at: dest)
        session.outputURL = dest
        session.outputFileType = .m4a
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                if session.status == .completed {
                    cont.resume()
                } else {
                    cont.resume(throwing: session.error ?? MediaError.exportFailed("Unknown error."))
                }
            }
        }
    }

    static func duration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        guard let t = try? await asset.load(.duration) else { return 0 }
        let s = t.seconds
        return s.isFinite ? s : 0
    }
}

struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return MovieFile(url: dest)
        }
    }
}
