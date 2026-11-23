import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: PackLibrary
    @EnvironmentObject private var bridge: MinecraftBridge
    @EnvironmentObject private var meta: LibraryMetaStore
    @EnvironmentObject private var downloads: DownloadManager

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", downloaded = "Downloaded", imported = "Imported", worlds = "Worlds", favorites = "Favorites", recent = "Recent"
        var id: String { rawValue }
    }

    @State private var importing = false
    @State private var filter: Filter = .all

    private var filtered: [PackItem] {
        let items = library.items
        switch filter {
        case .all: return items
        case .downloaded: return items.filter { meta.entry(for: $0.id).origin == .downloaded }
        case .imported: return items.filter { meta.entry(for: $0.id).origin == .imported }
        case .worlds: return items.filter { $0.kind == .mcworld || $0.kind == .mctemplate }
        case .favorites: return items.filter { meta.entry(for: $0.id).favorite }
        case .recent:
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            return items.filter { meta.entry(for: $0.id).addedAt > cutoff || $0.modified > cutoff }
        }
    }

    var body: some View {
        Screen {
            ScreenHeader(title: "Library", subtitle: "Your packs, worlds and add-ons")

            if let banner = library.banner { bannerView(banner) }

            Button { Haptics.tap(); importing = true } label: {
                Label(library.isWorking ? "Importing..." : "Import from Files", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(library.isWorking)

            NavigationLink { DownloadsView() } label: {
                HStack {
                    Label("Downloads", systemImage: "arrow.down.circle.fill").foregroundStyle(.white)
                    Spacer()
                    if downloads.activeCount > 0 {
                        Text("\(downloads.activeCount) active").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                }
                .glassCard(radius: 18, padding: 14)
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases) { option in
                        Button { Haptics.tap(); filter = option } label: {
                            Text(option.rawValue)
                                .font(.system(.footnote, design: .rounded).weight(.semibold))
                                .foregroundStyle(filter == option ? Color.black.opacity(0.85) : .white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(filter == option ? Theme.accent : Theme.graphite.opacity(0.8)))
                                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if filtered.isEmpty { emptyState } else {
                ForEach(filtered) { item in
                    NavigationLink { LibraryDetailView(itemID: item.id) } label: { row(item) }
                        .buttonStyle(.plain)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task {
                    await library.importFiles(urls)
                    for item in library.items where meta.entries[item.id] == nil { meta.update(item.id) { $0.origin = .imported } }
                }
            case .failure(let error):
                library.report(error: error.localizedDescription)
            }
        }
        .task { await library.reload() }
    }

    private func row(_ item: PackItem) -> some View {
        let entry = meta.entry(for: item.id)
        return HStack(spacing: 14) {
            Image(systemName: item.kind.symbol).font(.title3).foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName ?? item.title).font(.system(.headline, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                Text(item.subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
                HStack(spacing: 6) {
                    tag(entry.origin == .downloaded ? "Downloaded" : "Imported", color: Theme.accent)
                    if entry.lastHandedToMinecraft != nil { tag("Sent to Minecraft menu", color: Theme.warning) }
                }
            }
            Spacer(minLength: 6)
            Button {
                Haptics.tap()
                meta.update(item.id) { $0.favorite.toggle() }
            } label: {
                Image(systemName: entry.favorite ? "star.fill" : "star").foregroundStyle(entry.favorite ? Theme.warning : Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.favorite ? "Remove favorite" : "Add favorite")
        }
        .glassCard(radius: 22, padding: 14)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(color.opacity(0.14)))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 38)).foregroundStyle(Theme.accent)
            Text(library.items.isEmpty ? "Nothing here yet" : "Nothing in this filter")
                .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
            Text("Import a .mcpack, .mcaddon, .mcworld, .mctemplate or pack .zip, or download one from Discover.")
                .font(.footnote).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 26)
    }

    private func bannerView(_ banner: LibraryBanner) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? Theme.warning : Theme.accent)
            Text(banner.message).font(.footnote).foregroundStyle(.white.opacity(0.9)).frame(maxWidth: .infinity, alignment: .leading)
            Button { library.banner = nil } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondaryText) }
                .accessibilityLabel("Dismiss message")
        }
        .glassCard(radius: 18, padding: 14)
    }
}

struct LibraryDetailView: View {
    @EnvironmentObject private var library: PackLibrary
    @EnvironmentObject private var bridge: MinecraftBridge
    @EnvironmentObject private var meta: LibraryMetaStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String

    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var message: String?

    var body: some View {
        if let item = library.items.first(where: { $0.id == itemID }) {
            let entry = meta.entry(for: itemID)
            Screen {
                Text(entry.displayName ?? item.title).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.white)

                VStack(spacing: 10) {
                    InfoRow(label: "File", value: item.url.lastPathComponent)
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "Type", value: item.contents.isEmpty ? item.kind.title : item.contents.joined(separator: ", "))
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "Version", value: item.version ?? "Not stated")
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "Added", value: item.modified.formatted(date: .abbreviated, time: .shortened))
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "Origin", value: entry.origin == .downloaded ? "Downloaded by AETHER" : "Imported from Files")
                    if let source = entry.sourceProject {
                        Divider().overlay(Theme.hairline)
                        InfoRow(label: "Source", value: source)
                    }
                    if let hash = entry.sha1 {
                        Divider().overlay(Theme.hairline)
                        InfoRow(label: "SHA-1", value: String(hash.prefix(12)) + "...")
                    }
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Minecraft status").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                    Text(entry.lastHandedToMinecraft.map { "Handed to the Open In menu on \($0.formatted(date: .abbreviated, time: .shortened)). AETHER can't confirm Minecraft imported it." }
                         ?? "Stored in AETHER only. It hasn't been sent to Minecraft.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                .glassCard()

                if let message { Text(message).font(.footnote).foregroundStyle(Theme.warning) }

                Button { open(item) } label: { Label("Open in Minecraft", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(PrimaryButtonStyle())

                HStack(spacing: 12) {
                    ShareLink(item: item.url) { Label("Export", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button { newName = entry.displayName ?? item.title; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button { meta.update(itemID) { $0.favorite.toggle() } } label: {
                        Label(entry.favorite ? "Unfavorite" : "Favorite", systemImage: entry.favorite ? "star.slash" : "star")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete from AETHER", systemImage: "trash") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $renaming) {
                NavigationStack {
                    Form { TextField("Name", text: $newName) }
                        .navigationTitle("Rename")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { renaming = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    meta.update(itemID) { $0.displayName = newName.nilIfEmpty }
                                    renaming = false
                                }
                            }
                        }
                }
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
            }
            .confirmationDialog("Delete this file from AETHER?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await library.remove(item)
                        meta.remove(itemID)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only AETHER's copy is deleted. Anything already added to Minecraft stays there.")
            }
        } else {
            Screen { Text("This file is no longer in the library.").foregroundStyle(Theme.secondaryText) }
        }
    }

    private func open(_ item: PackItem) {
        Haptics.tap()
        guard bridge.status == .installed else {
            message = "Minecraft isn't installed, so there's nothing to open this file with."
            return
        }
        if DocumentOpener.presentOpenInMenu(for: item.url) {
            meta.update(itemID) { $0.lastHandedToMinecraft = Date() }
            message = nil
        } else {
            message = "iOS found no app that can open \(item.url.lastPathComponent)."
        }
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        Screen {
            Text("Downloads").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("Finished downloads sit in your AETHER library. They aren't in Minecraft until you send them through the Open In menu.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)

            if downloads.records.isEmpty {
                Text("No downloads yet. Find content on the Discover tab.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity).glassCard()
            }
            ForEach(downloads.records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.projectName ?? record.fileName).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(.white).lineLimit(2)
                            Text(record.fileName).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        }
                        Spacer()
                        stateLabel(record)
                    }
                    if record.isActive {
                        ProgressView(value: record.progress).tint(Theme.accent)
                        Text(record.state == .validating ? "Checking file" :
                                "\(ByteCountFormatter.string(fromByteCount: record.bytesWritten, countStyle: .file)) of \(record.totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: record.totalBytes, countStyle: .file) : "unknown")")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    if let error = record.errorMessage {
                        Text(error).font(.caption).foregroundStyle(record.state == .failed ? Theme.warning : Theme.secondaryText)
                    }
                    HStack(spacing: 10) {
                        if record.isActive {
                            Button { downloads.cancel(record.id) } label: { Label("Cancel", systemImage: "xmark") }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        if record.canRetry {
                            Button { downloads.retry(record.id) } label: { Label("Retry", systemImage: "arrow.clockwise") }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        if !record.isActive {
                            Button { downloads.remove(record.id) } label: { Label("Remove", systemImage: "trash") }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Theme.secondaryText)
                }
                .glassCard(radius: 20, padding: 14)
            }

            if downloads.records.contains(where: { !$0.isActive }) {
                Button { downloads.clearFinished() } label: { Label("Clear finished", systemImage: "trash") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func stateLabel(_ record: DownloadRecord) -> some View {
        let (text, color): (String, Color) = {
            switch record.state {
            case .queued: return ("Queued", Theme.secondaryText)
            case .downloading: return ("\(Int(record.progress * 100))%", .white)
            case .validating: return ("Checking", .white)
            case .completed: return ("In library", Theme.accent)
            case .failed: return ("Failed", Theme.warning)
            case .cancelled: return ("Cancelled", Theme.secondaryText)
            }
        }()
        return Text(text).font(.caption.weight(.bold)).foregroundStyle(color)
    }
}
