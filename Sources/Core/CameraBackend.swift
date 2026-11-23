import SwiftUI

enum CameraBackendError: LocalizedError {
    case noRuntime

    var errorDescription: String? {
        switch self {
        case .noRuntime:
            return "No Minecraft runtime is attached, so the camera was not changed."
        }
    }
}

/// The seam between AETHER's zoom UI and a real game camera.
/// A conforming backend must change the actual in-game camera (never scale a view or screenshot).
protocol CameraBackend {
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    func apply(zoomFactor: Double) throws
    func restore() throws
}

/// The only backend AETHER can honestly ship on stock iOS (see docs/TECHNICAL_REPORT.md, blockers 5 and 6).
struct UnavailableCameraBackend: CameraBackend {
    let isAvailable = false
    let unavailableReason = "iOS doesn't let AETHER run code inside Minecraft or reach its camera."

    func apply(zoomFactor: Double) throws { throw CameraBackendError.noRuntime }
    func restore() throws { throw CameraBackendError.noRuntime }
}

/// Tracks what the user asked for separately from what the backend actually did,
/// so the UI can never claim a zoom that didn't happen.
final class ZoomController: ObservableObject {
    @Published private(set) var requested = false
    @Published private(set) var applied = false
    @Published private(set) var message: String?

    private let backend: CameraBackend

    init(backend: CameraBackend = UnavailableCameraBackend()) {
        self.backend = backend
    }

    var backendAvailable: Bool { backend.isAvailable }
    var backendReason: String { backend.unavailableReason }

    func toggle(strength: Double) {
        requested.toggle()
        do {
            if requested {
                try backend.apply(zoomFactor: strength)
                applied = true
                message = "Zoom \(String(format: "%.1f", strength))x applied."
            } else {
                try backend.restore()
                applied = false
                message = "Camera restored."
            }
        } catch {
            applied = false
            message = "Not applied: \(error.localizedDescription)"
        }
    }

    func reset() {
        requested = false
        applied = false
        message = nil
        try? backend.restore()
    }
}
