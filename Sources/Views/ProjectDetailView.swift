import SwiftUI

struct ProjectDetailView: View {
    @EnvironmentObject private var downloads: DownloadManager
    let mod: CFMod
    let client: CurseForgeClient
    let versionFilter: String

    @State private var detail: CFMod?
    @State private var description = ""
    @State private var files: [CFFile] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var changelogs: [Int: String] = [:]
    @State private var pendingDuplicate: (file: CFFile, existing: String)?

    private var shown: CFMod { detail ?? mod }

    var body: some View {
        Screen {
            header

            if let notice {
                Label(notice, systemImage: "info.circle.fill").font(.footnote).foregroundStyle(Theme.accent).glassCard(radius: 16, padding: 12)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.warning)
            }

            if let shots = shown.screenshots, !shots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(shots, id: \.self) { shot in
                            AsyncImage(url: (shot.thumbnailUrl ?? shot.url).flatMap(URL.init(string:))) { phase in
                                if case .success(let image) = phase { image.resizable().scaledToFill() }
                                else { Rectangle().fill(Theme.graphite) }
                            }
                            .frame(width: 240, height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }

            if !description.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                    Text(description).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(24)
                }
                .glassCard()
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Files").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                if loading { ProgressView().tint(Theme.accent) }
                if !loading && files.isEmpty { Text("No files listed.").font(.footnote).foregroundStyle(Theme.secondaryText) }
                ForEach(files) { file in fileRow(file) }
            }
            .glassCard()

            if let site = shown.links?.websiteUrl.flatMap(URL.init(string:)) {
                Link(destination: site) { Label("Open on CurseForge", systemImage: "arrow.up.right.square") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .navigationTitle(mod.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .confirmationDialog("Already in your library", isPresented: Binding(get: { pendingDuplicate != nil },
                                                                           set: { if !$0 { pendingDuplicate = nil } }),
                            titleVisibility: .visible) {
            Button("Download again") {
                if let pending = pendingDuplicate { Task { await download(pending.file, allowDuplicate: true) } }
                pendingDuplicate = nil
            }
            Button("Cancel", role: .cancel) { pendingDuplicate = nil }
        } message: {
            Text("\(pendingDuplicate?.existing ?? "This file") was downloaded earlier.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: shown.logo?.thumbnailUrl.flatMap(URL.init(string:))) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Rectangle().fill(Theme.graphite) }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(shown.name).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
                Text("by " + (shown.authors?.map(\.name).joined(separator: ", ") ?? "unknown"))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                Label(ModRow.compact(shown.downloadCount ?? 0) + " downloads", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                if let summary = shown.summary?.nilIfEmpty {
                    Text(summary).font(.footnote).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private func fileRow(_ file: CFFile) -> some View {
        let matches = versionFilter.nilIfEmpty.map { filter in file.gameVersions?.contains(filter) == true }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                    Text([file.releaseLabel, file.fileLength.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
                          file.gameVersions?.prefix(3).joined(separator: ", ")].compactMap { $0 }.joined(separator: "  |  "))
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Button { Task { await download(file, allowDuplicate: false) } } label: { Image(systemName: "arrow.down.circle.fill").font(.title2) }
                    .accessibilityLabel("Download \(file.displayName)")
            }
            if let matches {
                Label(matches ? "Matches game version \(versionFilter)" : "Not listed for game version \(versionFilter)",
                      systemImage: matches ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(matches ? Theme.accent : Theme.warning)
            }
            if let log = changelogs[file.id] {
                Text(log.isEmpty ? "No changelog provided." : log).font(.caption).foregroundStyle(.white.opacity(0.8))
            } else {
                Button("Show changelog") { Task { await loadChangelog(file) } }
                    .font(.caption.weight(.semibold))
            }
            Divider().overlay(Theme.hairline)
        }
    }

    private func load() async {
        do {
            async let fullMod = client.mod(id: mod.id)
            async let text = client.description(modID: mod.id)
            async let fileList = client.files(modID: mod.id, gameVersion: nil)
            detail = try await fullMod
            description = HTMLText.plain(from: (try? await text) ?? "")
            files = try await fileList
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func loadChangelog(_ file: CFFile) async {
        do {
            let raw = try await client.changelog(modID: mod.id, fileID: file.id)
            changelogs[file.id] = HTMLText.plain(from: raw)
        } catch {
            notice = "Couldn't load the changelog: \(error.localizedDescription)"
        }
    }

    private func download(_ file: CFFile, allowDuplicate: Bool) async {
        notice = nil
        var url = file.downloadUrl.flatMap(URL.init(string:))
        if url == nil { url = try? await client.downloadURL(modID: mod.id, fileID: file.id) }
        guard let url else {
            notice = "The author doesn't allow downloads outside CurseForge. Use Open on CurseForge instead."
            return
        }
        switch downloads.enqueue(url: url, fileName: file.fileName, projectName: mod.name, projectID: mod.id,
                                 fileID: file.id, sha1: file.sha1, size: file.fileLength, allowDuplicate: allowDuplicate) {
        case .started: notice = "Download started. Follow it in Library, Downloads."
        case .duplicate(let existing): pendingDuplicate = (file, existing)
        case .rejected(let message): notice = message
        }
    }
}
