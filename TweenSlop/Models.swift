import Foundation
import CoreGraphics

struct Vec2: Codable, Equatable {
    var x: Double
    var y: Double
    static let zero = Vec2(x: 0, y: 0)
}

enum Easing: String, Codable, CaseIterable, Identifiable {
    case linear, easeIn, easeOut, easeInOut, back, bounce, elastic, hold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In-Out"
        case .back: return "Overshoot"
        case .bounce: return "Bounce"
        case .elastic: return "Elastic"
        case .hold: return "Hold (step)"
        }
    }

    func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t * t
        case .easeOut:
            let u = 1 - t
            return 1 - u * u * u
        case .easeInOut:
            return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .back:
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        case .bounce:
            let n1 = 7.5625
            let d1 = 2.75
            if t < 1 / d1 {
                return n1 * t * t
            } else if t < 2 / d1 {
                let u = t - 1.5 / d1
                return n1 * u * u + 0.75
            } else if t < 2.5 / d1 {
                let u = t - 2.25 / d1
                return n1 * u * u + 0.9375
            } else {
                let u = t - 2.625 / d1
                return n1 * u * u + 0.984375
            }
        case .elastic:
            if t <= 0 { return 0 }
            if t >= 1 { return 1 }
            let c4 = (2 * Double.pi) / 3
            return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
        case .hold:
            return 0
        }
    }
}

struct Keyframe: Codable, Identifiable, Equatable {
    var id = UUID()
    var frame: Int
    var rotation: Double
    var dx: Double
    var dy: Double
    var scale: Double
    var easing: Easing
}

struct Pose: Equatable {
    var rotation: Double
    var dx: Double
    var dy: Double
    var scale: Double

    init(rotation: Double = 0, dx: Double = 0, dy: Double = 0, scale: Double = 1) {
        self.rotation = rotation
        self.dx = dx
        self.dy = dy
        self.scale = scale
    }

    init(_ k: Keyframe) {
        self.init(rotation: k.rotation, dx: k.dx, dy: k.dy, scale: k.scale)
    }

    static let identity = Pose()
}

struct Part: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var imageFile: String?
    var parentID: UUID?
    var size: Vec2
    var pivot: Vec2
    var joint: Vec2
    var z: Int
    var keyframes: [Keyframe] = []
    var colorIndex: Int = 0
}

struct Body: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var position: Vec2
    var scale: Double = 1
    var parts: [Part]
    var visible: Bool = true
}

struct SoundClip: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var file: String
    var startFrame: Int = 0
    var volume: Double = 1
}

struct VideoClip: Codable, Equatable {
    var name: String
    var file: String
    var startFrame: Int = 0
}

struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var fps: Int = 24
    var durationFrames: Int = 120
    var canvasWidth: Double = 1080
    var canvasHeight: Double = 1920
    var bodies: [Body] = []
    var sounds: [SoundClip] = []
    var video: VideoClip?
    var modified: Date = Date()
}
