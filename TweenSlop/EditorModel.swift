import SwiftUI
import AVFoundation
import UIKit

enum PanelTab: String, CaseIterable, Identifiable {
    case rig = "Rig"
    case animate = "Animate"
    case media = "Media"
    var id: String { rawValue }
}

enum RigTool: String, CaseIterable, Identifiable {
    case pivot = "Set Pivot"
    case place = "Move Part"
    var id: String { rawValue }
}

enum PoseTool: String, CaseIterable, Identifiable {
    case rotate = "Rotate"
    case move = "Move"
    var id: String { rawValue }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var project: Project {
        didSet { scheduleSave() }
    }
    @Published var currentFrame = 0
    @Published var isPlaying = false
    @Published var selectedBodyID: UUID?
    @Published var selectedPartID: UUID?
    @Published var tab: PanelTab = .rig
    @Published var rigTool: RigTool = .pivot
    @Published var poseTool: PoseTool = .rotate
    @Published var player: AVPlayer? = nil
    @Published var errorMessage: String? = nil
    @Published var isBusy = false

    let store: ProjectStore
    let assetsURL: URL

    private var audioPlayers: [UUID: AVAudioPlayer] = [:]
    private var timer: Timer?
    private var saveTask: Task<Void, Never>?
    private var imageCache: [String: UIImage] = [:]
    private var playStartDate = Date()
    private var playStartFrame = 0
    private var videoStarted = false
    private var lastEasing: Easing = .easeInOut

    init(project: Project, store: ProjectStore) {
        self.project = project
        self.store = store
        self.assetsURL = ProjectStore.assetsFolder(for: project.id)
        self.selectedBodyID = project.bodies.first?.id
        self.selectedPartID = project.bodies.first?.parts.first?.id
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        reloadVideo()
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = project
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            self?.store.write(snapshot)
        }
    }

    func commit() {
        pause()
        saveTask?.cancel()
        var p = project
        p.modified = Date()
        store.commit(p)
    }

    // MARK: Selection helpers

    var bodyIndex: Int? { project.bodies.firstIndex { $0.id == selectedBodyID } }
    var selectedBody: Body? { project.bodies.first { $0.id == selectedBodyID } }
    var selectedPart: Part? { selectedBody?.parts.first { $0.id == selectedPartID } }
    var keyAtCurrent: Keyframe? { selectedPart?.keyframes.first { $0.frame == currentFrame } }

    func partByID(_ id: UUID) -> Part? {
        selectedBody?.parts.first { $0.id == id }
    }

    func selectBody(_ id: UUID) {
        selectedBodyID = id
        selectedPartID = project.bodies.first { $0.id == id }?.parts.first?.id
    }

    func mutatePart(_ id: UUID, _ change: (inout Part) -> Void) {
        guard let bi = bodyIndex,
              let pi = project.bodies[bi].parts.firstIndex(where: { $0.id == id }) else { return }
        change(&project.bodies[bi].parts[pi])
    }

    func mutateBody(_ change: (inout Body) -> Void) {
        guard let bi = bodyIndex else { return }
        change(&project.bodies[bi])
    }

    // MARK: Bodies and parts

    func addBody(humanoid: Bool) {
        let n = project.bodies.count + 1
        let size = CGSize(width: project.canvasWidth, height: project.canvasHeight)
        let body: Body
        if humanoid {
            body = Rig.humanoid(name: "Body \(n)", canvas: size)
        } else {
            body = Body(name: "Body \(n)", position: Vec2(x: size.width / 2, y: size.height / 2), parts: [])
        }
        project.bodies.append(body)
        selectedBodyID = body.id
        selectedPartID = body.parts.first?.id
    }

    func deleteSelectedBody() {
        guard let bi = bodyIndex else { return }
        project.bodies.remove(at: bi)
        selectedBodyID = project.bodies.first?.id
        selectedPartID = project.bodies.first?.parts.first?.id
    }

    func addPart() {
        guard let bi = bodyIndex else { return }
        let parts = project.bodies[bi].parts
        let parent = selectedPartID ?? parts.first?.id
        let part = Part(
            name: "Part \(parts.count + 1)",
            parentID: parent,
            size: Vec2(x: 160, y: 160),
            pivot: Vec2(x: 0.5, y: 0.5),
            joint: .zero,
            z: (parts.map { $0.z }.max() ?? 0) + 1,
            colorIndex: parts.count
        )
        project.bodies[bi].parts.append(part)
        selectedPartID = part.id
    }

    func deletePart(_ id: UUID) {
        guard let bi = bodyIndex, let part = partByID(id) else { return }
        let newParent = part.parentID
        let abs = Rig.restPosition(of: id, in: project.bodies[bi].parts)
        let base = newParent.map { Rig.restPosition(of: $0, in: project.bodies[bi].parts) } ?? Vec2.zero
        for i in project.bodies[bi].parts.indices where project.bodies[bi].parts[i].parentID == id {
            project.bodies[bi].parts[i].parentID = newParent
            project.bodies[bi].parts[i].joint.x += abs.x - base.x
            project.bodies[bi].parts[i].joint.y += abs.y - base.y
        }
        project.bodies[bi].parts.removeAll { $0.id == id }
        selectedPartID = project.bodies[bi].parts.first?.id
    }

    func setParent(_ id: UUID, _ newParent: UUID?) {
        guard let bi = bodyIndex else { return }
        let parts = project.bodies[bi].parts
        let abs = Rig.restPosition(of: id, in: parts)
        let base = newParent.map { Rig.restPosition(of: $0, in: parts) } ?? Vec2.zero
        mutatePart(id) { p in
            p.parentID = newParent
            p.joint = Vec2(x: abs.x - base.x, y: abs.y - base.y)
        }
    }

    // MARK: Images

    func image(for part: Part) -> UIImage? {
        guard let file = part.imageFile else { return nil }
        if let cached = imageCache[file] { return cached }
        if let img = UIImage(contentsOfFile: assetsURL.appendingPathComponent(file).path) {
            imageCache[file] = img
            return img
        }
        return nil
    }

    static func normalized(_ img: UIImage, maxSide: CGFloat = 2048) -> UIImage {
        let m = max(img.size.width, img.size.height)
        let k = m > maxSide ? maxSide / m : 1
        let newSize = CGSize(width: img.size.width * k, height: img.size.height * k)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func importImage(data: Data, partID: UUID) {
        guard let ui = UIImage(data: data) else {
            errorMessage = "Couldn't read that image."
            return
        }
        let norm = Self.normalized(ui)
        guard let png = norm.pngData() else {
            errorMessage = "Couldn't convert that image."
            return
        }
        let name = UUID().uuidString + ".png"
        do {
            try png.write(to: assetsURL.appendingPathComponent(name))
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        imageCache[name] = norm
        let aspect = Double(norm.size.width / max(norm.size.height, 1))
        mutatePart(partID) { p in
            p.imageFile = name
            let ref = max(p.size.x, p.size.y)
            p.size = aspect >= 1 ? Vec2(x: ref, y: ref / aspect) : Vec2(x: ref * aspect, y: ref)
        }
    }

    // MARK: Keyframes

    func upsertKeyframe(partID: UUID, pose: Pose) {
        let frame = currentFrame
        let ease = lastEasing
        mutatePart(partID) { p in
            if let i = p.keyframes.firstIndex(where: { $0.frame == frame }) {
                p.keyframes[i].rotation = pose.rotation
                p.keyframes[i].dx = pose.dx
                p.keyframes[i].dy = pose.dy
                p.keyframes[i].scale = pose.scale
            } else {
                if p.keyframes.isEmpty && frame > 0 {
                    p.keyframes.append(Keyframe(frame: 0, rotation: 0, dx: 0, dy: 0, scale: 1, easing: ease))
                }
                p.keyframes.append(Keyframe(frame: frame, rotation: pose.rotation, dx: pose.dx, dy: pose.dy, scale: pose.scale, easing: ease))
                p.keyframes.sort { $0.frame < $1.frame }
            }
        }
    }

    func editPose(partID: UUID, _ change: (inout Pose) -> Void) {
        guard let p = partByID(partID) else { return }
        var pose = Rig.pose(for: p, at: currentFrame)
        change(&pose)
        upsertKeyframe(partID: partID, pose: pose)
    }

    func addKeyframeHere() {
        guard let id = selectedPartID, let p = partByID(id) else { return }
        upsertKeyframe(partID: id, pose: Rig.pose(for: p, at: currentFrame))
    }

    func deleteKeyframeHere() {
        guard let id = selectedPartID else { return }
        let f = currentFrame
        mutatePart(id) { p in
            p.keyframes.removeAll { $0.frame == f }
        }
    }

    func setEasingHere(_ e: Easing) {
        guard let id = selectedPartID else { return }
        lastEasing = e
        let f = currentFrame
        mutatePart(id) { p in
            if let i = p.keyframes.firstIndex(where: { $0.frame == f }) {
                p.keyframes[i].easing = e
            }
        }
    }

    func clearKeyframes() {
        guard let id = selectedPartID else { return }
        mutatePart(id) { p in
            p.keyframes.removeAll()
        }
    }

    func jumpKey(forward: Bool) {
        guard let p = selectedPart else { return }
        let frames = p.keyframes.map { $0.frame }
        if forward {
            if let f = frames.first(where: { $0 > currentFrame }) { scrub(f) }
        } else {
            if let f = frames.last(where: { $0 < currentFrame }) { scrub(f) }
        }
    }

    // MARK: Project settings

    func setFPS(_ v: Int) {
        project.fps = max(1, min(60, v))
    }

    func setDuration(_ v: Int) {
        project.durationFrames = max(2, v)
        if currentFrame >= project.durationFrames { currentFrame = project.durationFrames - 1 }
    }

    func setCanvas(_ w: Double, _ h: Double) {
        project.canvasWidth = w
        project.canvasHeight = h
    }

    // MARK: Playback

    func scrub(_ f: Int) {
        if isPlaying { pause() }
        setFrame(f)
    }

    private func setFrame(_ f: Int) {
        currentFrame = max(0, min(f, project.durationFrames - 1))
        if !isPlaying { previewVideo() }
    }

    func play() {
        guard !isPlaying else { return }
        if currentFrame >= project.durationFrames - 1 { currentFrame = 0 }
        isPlaying = true
        playStartDate = Date()
        playStartFrame = currentFrame
        startMedia(from: currentFrame)
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        if isPlaying {
            isPlaying = false
            stopMedia()
        }
    }

    private func tick() {
        guard isPlaying else { return }
        let elapsed = Date().timeIntervalSince(playStartDate)
        let f = playStartFrame + Int(elapsed * Double(project.fps))
        if f >= project.durationFrames {
            stopMedia()
            currentFrame = 0
            playStartFrame = 0
            playStartDate = Date()
            startMedia(from: 0)
            return
        }
        if f != currentFrame { currentFrame = f }
        if !videoStarted, let v = project.video, let pl = player, f >= v.startFrame {
            videoStarted = true
            pl.seek(to: .zero)
            pl.play()
        }
    }

    private func audioPlayer(for clip: SoundClip) -> AVAudioPlayer? {
        if let p = audioPlayers[clip.id] { return p }
        let url = assetsURL.appendingPathComponent(clip.file)
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.prepareToPlay()
        audioPlayers[clip.id] = p
        return p
    }

    private func startMedia(from frame: Int) {
        let fps = Double(project.fps)
        let t = Double(frame) / fps
        for clip in project.sounds {
            guard let p = audioPlayer(for: clip) else { continue }
            p.volume = Float(clip.volume)
            let offset = t - Double(clip.startFrame) / fps
            if offset >= 0 {
                if offset < p.duration {
                    p.currentTime = offset
                    _ = p.play()
                }
            } else {
                p.currentTime = 0
                _ = p.play(atTime: p.deviceCurrentTime + (-offset))
            }
        }
        videoStarted = false
        if let v = project.video, let pl = player {
            let off = t - Double(v.startFrame) / fps
            if off >= 0 {
                videoStarted = true
                pl.seek(to: CMTime(seconds: off, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                pl.play()
            } else {
                pl.pause()
                pl.seek(to: .zero)
            }
        }
    }

    private func stopMedia() {
        for p in audioPlayers.values { p.stop() }
        player?.pause()
    }

    private func previewVideo() {
        guard let v = project.video, let pl = player else { return }
        let off = max(0, Double(currentFrame - v.startFrame) / Double(project.fps))
        pl.seek(to: CMTime(seconds: off, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Media import

    private func extendTimeline(toFit seconds: Double) {
        let frames = Int(ceil(seconds * Double(project.fps)))
        let capped = min(frames, project.fps * 600)
        if capped > project.durationFrames { project.durationFrames = capped }
    }

    func importSound(from url: URL) async {
        isBusy = true
        defer { isBusy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file = UUID().uuidString + ".m4a"
        let dest = assetsURL.appendingPathComponent(file)
        do {
            try await MediaTools.extractAudio(from: url, to: dest)
            let dur = await MediaTools.duration(of: dest)
            project.sounds.append(SoundClip(name: url.deletingPathExtension().lastPathComponent, file: file))
            extendTimeline(toFit: dur)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importVideo(from url: URL) async {
        isBusy = true
        defer { isBusy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        let file = UUID().uuidString + "." + ext
        let dest = assetsURL.appendingPathComponent(file)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if let old = project.video {
            try? FileManager.default.removeItem(at: assetsURL.appendingPathComponent(old.file))
        }
        project.video = VideoClip(name: url.deletingPathExtension().lastPathComponent, file: file)
        reloadVideo()
        extendTimeline(toFit: await MediaTools.duration(of: dest))
    }

    func extractVideoAudio() async {
        guard let v = project.video else { return }
        isBusy = true
        defer { isBusy = false }
        let src = assetsURL.appendingPathComponent(v.file)
        let file = UUID().uuidString + ".m4a"
        let dest = assetsURL.appendingPathComponent(file)
        do {
            try await MediaTools.extractAudio(from: src, to: dest)
            project.sounds.append(SoundClip(name: v.name + " (audio)", file: file, startFrame: v.startFrame))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeVideo() {
        if let v = project.video {
            try? FileManager.default.removeItem(at: assetsURL.appendingPathComponent(v.file))
        }
        project.video = nil
        reloadVideo()
    }

    func setVideoStart(_ frame: Int) {
        project.video?.startFrame = max(0, frame)
        previewVideo()
    }

    func reloadVideo() {
        player?.pause()
        if let v = project.video {
            let pl = AVPlayer(url: assetsURL.appendingPathComponent(v.file))
            pl.isMuted = true
            player = pl
        } else {
            player = nil
        }
    }

    func updateSound(_ id: UUID, _ change: (inout SoundClip) -> Void) {
        guard let i = project.sounds.firstIndex(where: { $0.id == id }) else { return }
        change(&project.sounds[i])
        audioPlayers[id]?.volume = Float(project.sounds[i].volume)
    }

    func removeSound(_ id: UUID) {
        guard let clip = project.sounds.first(where: { $0.id == id }) else { return }
        audioPlayers[id]?.stop()
        audioPlayers[id] = nil
        try? FileManager.default.removeItem(at: assetsURL.appendingPathComponent(clip.file))
        project.sounds.removeAll { $0.id == id }
    }
}
