import SwiftUI

@MainActor
final class DiscoverModel: ObservableObject {
    enum Phase: Equatable { case needsSetup, loading, ready, failed(String) }

    @Published var phase: Phase = .loading
    @Published var classes: [CFCategory] = []
    @Published var selectedClass: Int?
    @Published var query = ""
    @Published var sort: CFSort = .popularity
    @Published var version = ""
    @Published private(set) var results: [CFMod] = []
    @Published private(set) var total = 0
    @Published private(set) var isSearching = false

    private(set) var client: CurseForgeClient?
    private var gameID: Int?

    var canLoadMore: Bool { results.count < total }

    func bootstrap() async {
        guard let client = CurseForgeClient.fromSettings() else { phase = .needsSetup; return }
        self.client = client
        phase = .loading
        do {
            let games = try await client.games()
            guard let bedrock = games.first(where: { $0.name.localizedCaseInsensitiveContains("bedrock") }) else {
                phase = .failed("CurseForge doesn't list a Minecraft Bedrock game for this key.")
                return
            }
            gameID = bedrock.id
            let categories = try await client.categories(gameID: bedrock.id)
            classes = categories.filter { $0.isClass == true }.sorted { $0.name < $1.name }
            phase = .ready
            await search(reset: true)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func search(reset: Bool) async {
        guard let client, let gameID else { return }
        if reset { results = []; total = 0 }
        isSearching = true
        defer { isSearching = false }
        do {
            let page = try await client.search(gameID: gameID, classID: selectedClass, text: query,
                                               sort: sort, version: version, index: reset ? 0 : results.count)
            if Task.isCancelled { return }
            results.append(contentsOf: page.data)
            total = page.pagination?.totalCount ?? results.count
            if phase != .ready { phase = .ready }
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            phase = .failed(error.localizedDescription)
        }
    }
}

struct DiscoverView: View {
    @StateObject private var model = DiscoverModel()

    private struct SearchKey: Equatable {
        let query: String
        let classID: Int?
        let sort: CFSort
        let version: String
    }

    var body: some View {
        Screen {
            ScreenHeader(title: "Discover", subtitle: "Minecraft Bedrock content from CurseForge")

            switch model.phase {
            case .needsSetup:
                CurseForgeSetupCard { Task { await model.bootstrap() } }
            case .loading:
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 40)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Theme.warning)
                    Button { Task { await model.bootstrap() } } label: { Label("Try again", systemImage: "arrow.clockwise") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .glassCard()
            case .ready:
                controls
                resultList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if model.phase == .loading { await model.bootstrap() } }
        .task(id: SearchKey(query: model.query, classID: model.selectedClass, sort: model.sort, version: model.version)) {
            guard model.phase == .ready else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            await model.search(reset: true)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
                TextField("Search CurseForge", text: $model.query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(.white)
                    .submitLabel(.search)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.graphite.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: model.selectedClass == nil) { model.selectedClass = nil }
                    ForEach(model.classes) { category in
                        chip(category.name, selected: model.selectedClass == category.id) { model.selectedClass = category.id }
                    }
                }
            }

            HStack(spacing: 12) {
                Picker("Sort", selection: $model.sort) {
                    ForEach(CFSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).tint(Theme.accent)
                Spacer()
                TextField("Game version", text: $model.version)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing).foregroundStyle(.white)
                    .frame(maxWidth: 130)
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Text(title)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(selected ? Color.black.opacity(0.85) : .white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(selected ? Theme.accent : Theme.graphite.opacity(0.8)))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultList: some View {
        if model.results.isEmpty && !model.isSearching {
            Text("No projects match. Try a different search, category or game version.")
                .font(.footnote).foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity).padding(.top, 24)
        }
        ForEach(model.results) { mod in
            if let client = model.client {
                NavigationLink { ProjectDetailView(mod: mod, client: client, versionFilter: model.version) } label: { ModRow(mod: mod) }
                    .buttonStyle(.plain)
            }
        }
        if model.isSearching { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity) }
        if model.canLoadMore && !model.isSearching {
            Button { Task { await model.search(reset: false) } } label: { Label("Load more", systemImage: "chevron.down") }
                .buttonStyle(SecondaryButtonStyle())
        }
    }
}

struct ModRow: View {
    let mod: CFMod

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: mod.logo?.thumbnailUrl.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: Rectangle().fill(Theme.graphite).overlay(Image(systemName: "photo").foregroundStyle(Theme.secondaryText))
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(mod.name).font(.system(.headline, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                Text("by " + (mod.authors?.map(\.name).joined(separator: ", ") ?? "unknown"))
                    .font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                if let summary = mod.summary?.nilIfEmpty {
                    Text(summary).font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                }
                Label(Self.compact(mod.downloadCount ?? 0) + " downloads", systemImage: "arrow.down.circle")
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }
        .glassCard(radius: 22, padding: 14)
    }

    static func compact(_ value: Double) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 1_000...: return String(format: "%.1fK", value / 1_000)
        default: return String(Int(value))
        }
    }
}

struct CurseForgeSetupCard: View {
    var onSaved: () -> Void = {}
    @State private var key = ""
    @State private var proxy = UserDefaults.standard.string(forKey: CurseForgeClient.proxyKey) ?? ""
    @State private var hasKey = Keychain.get(CurseForgeClient.keychainKey) != nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect CurseForge").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
            Text("AETHER ships without an API key, because a key inside an app can be extracted. Paste your own key from console.curseforge.com (stored in the Keychain), or enter the address of a proxy you run that holds the key.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)

            SecureField(hasKey ? "Key saved. Paste a new one to replace it" : "CurseForge API key", text: $key)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.graphite.opacity(0.7)))
                .foregroundStyle(.white)
            TextField("Proxy address (optional), https://...", text: $proxy)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .padding(12).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.graphite.opacity(0.7)))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Button {
                    if let trimmed = key.nilIfEmpty { Keychain.set(trimmed, for: CurseForgeClient.keychainKey) }
                    UserDefaults.standard.set(proxy.nilIfEmpty, forKey: CurseForgeClient.proxyKey)
                    key = ""
                    hasKey = Keychain.get(CurseForgeClient.keychainKey) != nil
                    onSaved()
                } label: { Label("Save", systemImage: "checkmark") }
                    .buttonStyle(SecondaryButtonStyle())

                if hasKey {
                    Button(role: .destructive) {
                        Keychain.delete(CurseForgeClient.keychainKey)
                        hasKey = false
                    } label: { Label("Remove key", systemImage: "trash") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .glassCard()
    }
}
