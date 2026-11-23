import SwiftUI

struct VersionsView: View {
    @EnvironmentObject private var versions: VersionStore
    @EnvironmentObject private var bridge: MinecraftBridge
    @State private var showingAdd = false
    @State private var importingPlist = false

    var body: some View {
        Screen {
            ScreenHeader(title: "Versions", subtitle: "Track versions and keep each one's data separate")

            VStack(alignment: .leading, spacing: 10) {
                Text("On this device").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                InfoRow(label: "Official Minecraft", value: bridge.status == .installed ? "Installed" : (bridge.status == .notInstalled ? "Not found" : "Checking"))
                InfoRow(label: "Version", value: "Unknown to AETHER")
                Text("iOS doesn't expose another app's version. Record it yourself below, or import the Info.plist from a copy you own.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .glassCard()

            blockedCard

            HStack(spacing: 12) {
                Button { Haptics.tap(); importingPlist = true } label: { Label("Import Info.plist", systemImage: "doc.badge.plus") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { Haptics.tap(); showingAdd = true } label: { Label("Add manually", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
            }

            if let error = versions.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(Theme.warning)
            }

            if versions.records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 34)).foregroundStyle(Theme.accent)
                    Text("No versions recorded").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                    Text("Each record gets its own worlds, packs and config folders inside AETHER.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .glassCard(padding: 24)
            } else {
                ForEach(versions.records) { record in
                    NavigationLink { VersionDetailView(record: record) } label: { row(record) }
                        .buttonStyle(.plain)
                }
            }

            if let url = VersionStore.releaseNotesURL {
                Link(destination: url) { Label("Official Bedrock release notes", systemImage: "arrow.up.right.square") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingAdd) { AddVersionSheet() }
        .fileImporter(isPresented: $importingPlist, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { versions.addFromInfoPlist(url) }
        }
    }

    private var blockedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Installing other versions is blocked", systemImage: "lock.fill")
                .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
            Text("The App Store provides one Minecraft build, and iOS won't run a second Minecraft executable or a copy placed inside AETHER. AETHER doesn't offer version downloads because there is no legitimate source or mechanism for them. See Settings, Runtime investigation.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .glassCard()
    }

    private func row(_ record: VersionRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: record.id == versions.activeID ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(record.id == versions.activeID ? Theme.accent : Theme.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Minecraft \(record.versionName)").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                Text([record.build.map { "build \($0)" }, record.source.rawValue].compactMap { $0 }.joined(separator: "  |  "))
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
        }
        .glassCard(radius: 22, padding: 16)
    }
}

private struct AddVersionSheet: View {
    @EnvironmentObject private var versions: VersionStore
    @Environment(\.dismiss) private var dismiss
    @State private var version = ""
    @State private var build = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Version") {
                    TextField("Version, for example 1.26.32", text: $version)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Build (optional)", text: $build)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Notes") { TextField("Optional", text: $notes, axis: .vertical) }
            }
            .navigationTitle("Add version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        versions.addManual(version: version, build: build, notes: notes)
                        if versions.lastError == nil { dismiss() }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct VersionDetailView: View {
    @EnvironmentObject private var versions: VersionStore
    @Environment(\.dismiss) private var dismiss
    let record: VersionRecord
    @State private var confirmingDelete = false
    @State private var repairMessage: String?
    @State private var notes = ""
    @State private var usage: Int64 = 0

    var body: some View {
        let compatibility = versions.compatibility(of: record)
        Screen {
            VStack(alignment: .leading, spacing: 4) {
                Text("Minecraft \(record.versionName)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text(record.source.rawValue).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }

            VStack(spacing: 12) {
                InfoRow(label: "Build", value: record.build ?? "Not recorded")
                Divider().overlay(Theme.hairline)
                InfoRow(label: "Bundle ID", value: record.bundleID)
                Divider().overlay(Theme.hairline)
                InfoRow(label: "Minimum iOS", value: record.minimumOS ?? "Not recorded")
                Divider().overlay(Theme.hairline)
                InfoRow(label: "AETHER data", value: ByteCountFormatter.string(fromByteCount: usage, countStyle: .file))
            }
            .glassCard()

            Label(compatibility.text,
                  systemImage: compatibility.compatible == false ? "exclamationmark.triangle.fill" : "iphone")
                .font(.footnote)
                .foregroundStyle(compatibility.compatible == false ? Theme.warning : Theme.secondaryText)
                .glassCard(radius: 18, padding: 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("Launching").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                Text("Play always opens whichever Minecraft is installed from the App Store. AETHER can't launch this version separately or confirm which version is installed.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .glassCard()

            TextField("Notes", text: $notes, axis: .vertical)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.graphite.opacity(0.6)))
                .foregroundStyle(.white)
                .onSubmit { versions.setNotes(notes, for: record) }

            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    versions.activeID = record.id
                } label: { Label(versions.activeID == record.id ? "Active" : "Set active", systemImage: "checkmark.circle") }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(versions.activeID == record.id)

                Button {
                    Haptics.tap()
                    repairMessage = versions.repair(record).summary
                } label: { Label("Repair", systemImage: "wrench.and.screwdriver") }
                    .buttonStyle(SecondaryButtonStyle())

                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete data", systemImage: "trash") }
                    .buttonStyle(SecondaryButtonStyle())
            }

            if let repairMessage {
                Text(repairMessage).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .navigationTitle("Version")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog("Delete this version's AETHER data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete record and data", role: .destructive) {
                versions.remove(record)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the record and AETHER's folders for it. Minecraft itself and its own worlds aren't touched.")
        }
        .task {
            notes = record.notes
            usage = versions.usage(of: record)
        }
        .onDisappear { versions.setNotes(notes, for: record) }
    }
}
