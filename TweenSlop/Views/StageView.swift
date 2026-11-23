import SwiftUI

struct StageView: View {
    @ObservedObject var model: EditorModel
    @State private var dragLast: CGPoint?

    private static let palette: [Color] = [.red, .orange, .yellow, .green, .teal, .blue, .purple, .pink]
    private var isRig: Bool { model.tab == .rig }

    var body: some View {
        GeometryReader { geo in
            let cw = CGFloat(model.project.canvasWidth)
            let ch = CGFloat(model.project.canvasHeight)
            let s = max(min(geo.size.width / cw, geo.size.height / ch), 0.001)
            ZStack {
                Color(white: 0.13)
                if model.project.video != nil, let pl = model.player {
                    VideoLayerView(player: pl)
                }
                canvas(scale: s)
                    .contentShape(Rectangle())
                    .gesture(drag(scale: s))
            }
            .frame(width: cw * s, height: ch * s)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(hintText)
                    .font(.caption2)
                    .padding(6)
                    .background(Color.black.opacity(0.6), in: Capsule())
                    .padding(6)
                    .allowsHitTesting(false)
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private var hintText: String {
        if model.project.bodies.isEmpty { return "Rig tab → New Body" }
        if isRig {
            return model.rigTool == .pivot ? "Drag to move the selected pivot" : "Drag to move the selected part"
        }
        return model.poseTool == .rotate ? "Drag a part to rotate it around its pivot" : "Drag a part to move it"
    }

    private func canvas(scale s: CGFloat) -> some View {
        let bodies = model.project.bodies
        let frame = model.currentFrame
        let rig = isRig
        let selBody = model.selectedBodyID
        let selPart = model.selectedPartID
        let showSel = !model.isPlaying
        let allParts = bodies.flatMap { $0.parts }
        let hasImage = Set(allParts.filter { model.image(for: $0) != nil }.map { $0.id })

        return Canvas { context, _ in
            var ctx = context
            ctx.scaleBy(x: s, y: s)
            for body in bodies where body.visible {
                let world = Rig.world(for: body, frame: frame, rest: rig)
                let isSel = showSel && body.id == selBody
                StageView.drawParts(ctx, body: body, world: world, hasImage: hasImage, selected: isSel ? selPart : nil)
                if isSel {
                    StageView.drawRig(ctx, body: body, world: world, selected: selPart, scale: s)
                }
            }
        } symbols: {
            ForEach(allParts) { part in
                if let ui = model.image(for: part) {
                    Image(uiImage: ui)
                        .resizable()
                        .frame(width: CGFloat(part.size.x), height: CGFloat(part.size.y))
                        .tag(part.id)
                }
            }
        }
    }

    private static func drawParts(_ ctx: GraphicsContext, body: Body, world: [UUID: CGAffineTransform], hasImage: Set<UUID>, selected: UUID?) {
        for part in body.parts.sorted(by: { $0.z < $1.z }) {
            guard let t = world[part.id] else { continue }
            var c = ctx
            c.transform = t.concatenating(ctx.transform)
            let rect = CGRect(
                x: -part.pivot.x * part.size.x,
                y: -part.pivot.y * part.size.y,
                width: part.size.x,
                height: part.size.y
            )
            if hasImage.contains(part.id), let sym = c.resolveSymbol(id: part.id) {
                c.draw(sym, at: rect.origin, anchor: .topLeading)
            } else {
                let color = palette[part.colorIndex % palette.count]
                let path = Path(roundedRect: rect, cornerRadius: 16)
                c.fill(path, with: .color(color.opacity(0.55)))
                c.stroke(path, with: .color(color), lineWidth: 3)
                c.draw(
                    Text(part.name).font(.system(size: 30, weight: .bold)).foregroundColor(.white),
                    at: CGPoint(x: rect.midX, y: rect.midY)
                )
            }
            if part.id == selected {
                c.stroke(Path(rect), with: .color(.red), style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
            }
        }
    }

    private static func drawRig(_ ctx: GraphicsContext, body: Body, world: [UUID: CGAffineTransform], selected: UUID?, scale s: CGFloat) {
        for part in body.parts {
            guard let t = world[part.id], let pid = part.parentID, let pt = world[pid] else { continue }
            var line = Path()
            line.move(to: CGPoint.zero.applying(pt))
            line.addLine(to: CGPoint.zero.applying(t))
            ctx.stroke(line, with: .color(Color.white.opacity(0.5)), lineWidth: 2 / s)
        }
        for part in body.parts {
            guard let t = world[part.id] else { continue }
            let p = CGPoint.zero.applying(t)
            let isSel = part.id == selected
            let r: CGFloat = (isSel ? 11 : 7) / s
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(dot, with: .color(isSel ? Color.red : Color.white))
            ctx.stroke(dot, with: .color(Color.black), lineWidth: 1.5 / s)
        }
    }

    private func drag(scale s: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if model.isPlaying { model.pause() }
                let p = CGPoint(x: value.location.x / s, y: value.location.y / s)
                guard let last = dragLast else {
                    dragLast = p
                    begin(at: p, scale: s)
                    return
                }
                dragLast = p
                update(from: last, to: p)
            }
            .onEnded { _ in dragLast = nil }
    }

    private func begin(at p: CGPoint, scale s: CGFloat) {
        guard let body = model.selectedBody else { return }
        let world = Rig.world(for: body, frame: model.currentFrame, rest: isRig)
        if isRig {
            var bestID: UUID?
            var bestDist = 40 / s
            for part in body.parts {
                guard let t = world[part.id] else { continue }
                let pv = CGPoint.zero.applying(t)
                let d = hypot(pv.x - p.x, pv.y - p.y)
                if d < bestDist {
                    bestDist = d
                    bestID = part.id
                }
            }
            if let id = bestID {
                model.selectedPartID = id
                return
            }
        }
        for part in body.parts.sorted(by: { $0.z > $1.z }) {
            guard let t = world[part.id] else { continue }
            let local = p.applying(t.inverted())
            let rect = CGRect(
                x: -part.pivot.x * part.size.x,
                y: -part.pivot.y * part.size.y,
                width: part.size.x,
                height: part.size.y
            )
            if rect.contains(local) {
                model.selectedPartID = part.id
                return
            }
        }
    }

    private func update(from last: CGPoint, to p: CGPoint) {
        guard let body = model.selectedBody,
              let pid = model.selectedPartID,
              let part = body.parts.first(where: { $0.id == pid }) else { return }
        let dx = p.x - last.x
        let dy = p.y - last.y

        if isRig {
            let k = CGFloat(max(body.scale, 0.01))
            let bx = Double(dx / k)
            let by = Double(dy / k)
            switch model.rigTool {
            case .pivot:
                model.mutatePart(pid) { q in
                    q.pivot.x += bx / max(q.size.x, 1)
                    q.pivot.y += by / max(q.size.y, 1)
                    q.joint.x += bx
                    q.joint.y += by
                }
            case .place:
                model.mutatePart(pid) { q in
                    q.joint.x += bx
                    q.joint.y += by
                }
            }
            return
        }

        let world = Rig.world(for: body, frame: model.currentFrame, rest: false)
        switch model.poseTool {
        case .rotate:
            guard let t = world[pid] else { return }
            let pv = CGPoint.zero.applying(t)
            let r0 = hypot(last.x - pv.x, last.y - pv.y)
            let r1 = hypot(p.x - pv.x, p.y - pv.y)
            guard r0 > 20, r1 > 20 else { return }
            var da = atan2(p.y - pv.y, p.x - pv.x) - atan2(last.y - pv.y, last.x - pv.x)
            while da > .pi { da -= 2 * .pi }
            while da < -.pi { da += 2 * .pi }
            let deg = Double(da) * 180 / Double.pi
            model.editPose(partID: pid) { $0.rotation += deg }
        case .move:
            var parentT = Rig.baseTransform(body)
            if let ppid = part.parentID, let pt = world[ppid] { parentT = pt }
            let inv = parentT.inverted()
            let lx = Double(inv.a * dx + inv.c * dy)
            let ly = Double(inv.b * dx + inv.d * dy)
            model.editPose(partID: pid) { pose in
                pose.dx += lx
                pose.dy += ly
            }
        }
    }
}
