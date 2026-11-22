import SwiftUI
import UniformTypeIdentifiers

struct PacksView: View {
    @EnvironmentObject private var library: PackLibrary
    @EnvironmentObject private var bridge: MinecraftBridge
    @State private var importing = false
    @State private var pendingDelete: PackItem?

    var body: some View {
        Screen {
            ScreenHeader(title: "Packs", subtitle: "Import packs, worlds and add-ons, then send them to Minecraft")

            if let banner = library.banner {
                bannerView(banner)
            }

            Button {
                Haptics.tap()
                importing = true
            } label: {
                Label(library.isWorking ? "Importing..." : "Import from Files", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(library.isWorking)

            if library.items.isEmpty {
                emptyState
            } else {
                ForEach(library.items) { item in
                    PackRow(item: item,
                            onOpen: { open(item) },
                            onDelete: { pendingDelete = item })
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await library.importFiles(urls) }
            case .failure(let error):
                library.report(error: error.localizedDescription)
            }
        }
        .confirmationDialog("Remove this file from AETHER?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Remove \(pendingDelete?.title ?? "file")", role: .destructive) {
                if let item = pendingDelete { Task { await library.remove(item) } }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This only deletes AETHER's copy. Anything already added to Minecraft stays there.")
        }
        .task { await library.reload() }
    }

    private func open(_ item: PackItem) {
        Haptics.tap()
        guard bridge.status == .installed else {
            library.report(error: "Minecraft isn't installed, so there's nothing to open this file with.")
            return
        }
        if !DocumentOpener.presentOpenInMenu(for: item.url) {
            library.report(error: "iOS found no app that can open \(item.url.lastPathComponent).")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 38))
                .foregroundStyle(Theme.accent)
            Text("Nothing imported yet")
                .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
            Text("Import a .mcpack, .mcaddon, .mcworld, .mctemplate or a pack .zip from the Files app.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 26)
    }

    private func bannerView(_ banner: LibraryBanner) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? Theme.warning : Theme.accent)
            Text(banner.message)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                library.banner = nil
            } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.secondaryText)
            }
            .accessibilityLabel("Dismiss message")
        }
        .glassCard(radius: 18, padding: 14)
    }
}

private struct PackRow: View {
    let item: PackItem
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: item.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    Label("Open in Minecraft", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(SecondaryButtonStyle())

                ShareLink(item: item.url) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer(minLength: 0)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.warning)
                        .padding(10)
                }
                .accessibilityLabel("Remove \(item.title)")
            }
        }
        .glassCard(radius: 22, padding: 16)
    }
}
