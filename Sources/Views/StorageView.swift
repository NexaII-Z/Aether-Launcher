import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var library: PackLibrary
    @State private var sizes: [StorageBucket: Int64] = [:]
    @State private var librarySize: Int64 = 0

    var body: some View {
        Screen {
            Text("Storage").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("Everything here is inside AETHER's own sandbox. AETHER can't see Minecraft's private data.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)

            VStack(spacing: 12) {
                row("Library (Files-visible)", "shippingbox.fill", librarySize, clear: nil)
                ForEach(StorageBucket.allCases) { bucket in
                    Divider().overlay(Theme.hairline)
                    row(bucket.title, bucket.symbol, sizes[bucket] ?? 0, clear: bucket.isClearable ? bucket : nil)
                }
            }
            .glassCard()
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await measure() }
    }

    private func row(_ title: String, _ symbol: String, _ bytes: Int64, clear: StorageBucket?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 26)
            Text(title).font(.subheadline).foregroundStyle(.white)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.footnote).foregroundStyle(Theme.secondaryText)
            if let clear {
                Button("Clear") {
                    Haptics.tap()
                    AetherStorage.clear(clear)
                    Task { await measure() }
                }
                .font(.footnote.weight(.semibold))
            }
        }
    }

    private func measure() async {
        let result = await Task.detached(priority: .utility) { () -> ([StorageBucket: Int64], Int64) in
            var map: [StorageBucket: Int64] = [:]
            for bucket in StorageBucket.allCases { map[bucket] = AetherStorage.size(of: AetherStorage.url(for: bucket)) }
            return (map, AetherStorage.size(of: AetherStorage.libraryURL))
        }.value
        sizes = result.0
        librarySize = result.1
    }
}
