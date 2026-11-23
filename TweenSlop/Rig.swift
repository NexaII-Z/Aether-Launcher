import Foundation
import CoreGraphics

enum Rig {
    static func pose(for part: Part, at frame: Int) -> Pose {
        let k = part.keyframes
        guard let first = k.first, let last = k.last else { return .identity }
        if frame <= first.frame { return Pose(first) }
        if frame >= last.frame { return Pose(last) }
        for i in 0..<(k.count - 1) {
            let a = k[i]
            let b = k[i + 1]
            if frame >= a.frame && frame <= b.frame {
                let span = Double(b.frame - a.frame)
                let t = span <= 0 ? 1 : Double(frame - a.frame) / span
                let e = t >= 1 ? 1 : a.easing.apply(t)
                return Pose(
                    rotation: a.rotation + (b.rotation - a.rotation) * e,
                    dx: a.dx + (b.dx - a.dx) * e,
                    dy: a.dy + (b.dy - a.dy) * e,
                    scale: a.scale + (b.scale - a.scale) * e
                )
            }
        }
        return Pose(last)
    }

    static func baseTransform(_ body: PuppetBody) -> CGAffineTransform {
        CGAffineTransform(translationX: CGFloat(body.position.x), y: CGFloat(body.position.y))
            .scaledBy(x: CGFloat(body.scale), y: CGFloat(body.scale))
    }

    static func world(for body: PuppetBody, frame: Int, rest: Bool) -> [UUID: CGAffineTransform] {
        var result: [UUID: CGAffineTransform] = [:]
        let byID = Dictionary(uniqueKeysWithValues: body.parts.map { ($0.id, $0) })
        let base = baseTransform(body)

        func resolve(_ part: Part, depth: Int) -> CGAffineTransform {
            if let cached = result[part.id] { return cached }
            var parentT = base
            if depth < 64, let pid = part.parentID, let parent = byID[pid] {
                parentT = resolve(parent, depth: depth + 1)
            }
            let p = rest ? Pose.identity : pose(for: part, at: frame)
            let local = CGAffineTransform.identity
                .translatedBy(x: CGFloat(part.joint.x + p.dx), y: CGFloat(part.joint.y + p.dy))
                .rotated(by: CGFloat(p.rotation * Double.pi / 180))
                .scaledBy(x: CGFloat(p.scale), y: CGFloat(p.scale))
            let w = local.concatenating(parentT)
            result[part.id] = w
            return w
        }

        for part in body.parts { _ = resolve(part, depth: 0) }
        return result
    }

    static func descendants(of id: UUID, in parts: [Part]) -> Set<UUID> {
        var found = Set<UUID>()
        var frontier = [id]
        while let current = frontier.popLast() {
            for p in parts where p.parentID == current && !found.contains(p.id) {
                found.insert(p.id)
                frontier.append(p.id)
            }
        }
        return found
    }

    static func restPosition(of id: UUID, in parts: [Part]) -> Vec2 {
        let byID = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0) })
        var x = 0.0
        var y = 0.0
        var cur: Part? = byID[id]
        var steps = 0
        while let p = cur, steps < 64 {
            x += p.joint.x
            y += p.joint.y
            cur = p.parentID.flatMap { byID[$0] }
            steps += 1
        }
        return Vec2(x: x, y: y)
    }

    static func humanoid(name: String, canvas: CGSize) -> PuppetBody {
        func make(_ n: String, _ w: Double, _ h: Double, pivot: (Double, Double), joint: (Double, Double), z: Int, parent: UUID?, color: Int) -> Part {
            Part(name: n, parentID: parent, size: Vec2(x: w, y: h), pivot: Vec2(x: pivot.0, y: pivot.1), joint: Vec2(x: joint.0, y: joint.1), z: z, colorIndex: color)
        }
        let torso = make("Torso", 260, 380, pivot: (0.5, 0.5), joint: (0, 0), z: 1, parent: nil, color: 0)
        let head = make("Head", 200, 200, pivot: (0.5, 0.9), joint: (0, -180), z: 2, parent: torso.id, color: 1)
        let armL = make("Left Arm", 90, 300, pivot: (0.5, 0.08), joint: (150, -150), z: 3, parent: torso.id, color: 2)
        let armR = make("Right Arm", 90, 300, pivot: (0.5, 0.08), joint: (-150, -150), z: 3, parent: torso.id, color: 3)
        let legL = make("Left Leg", 110, 340, pivot: (0.5, 0.06), joint: (65, 170), z: 0, parent: torso.id, color: 4)
        let legR = make("Right Leg", 110, 340, pivot: (0.5, 0.06), joint: (-65, 170), z: 0, parent: torso.id, color: 5)
        return PuppetBody(
            name: name,
            position: Vec2(x: Double(canvas.width) / 2, y: Double(canvas.height) / 2),
            parts: [torso, head, armL, armR, legL, legR]
        )
    }
}
