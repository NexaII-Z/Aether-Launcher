import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var account: AccountManager
    @AppStorage(AccountManager.clientIDKey) private var clientID = ""

    var body: some View {
        Screen {
            Text("Microsoft account").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)

            if let profile = account.profile, account.state == .signedIn || account.state == .signingIn {
                HStack(spacing: 14) {
                    AsyncImage(url: profile.avatarURL.flatMap(URL.init(string:))) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(Theme.accent) }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.gamertag).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(.white)
                        if let score = profile.gamerscore { Text("Gamerscore \(score)").font(.footnote).foregroundStyle(Theme.secondaryText) }
                        if let xuid = profile.xuid { Text("XUID \(xuid)").font(.caption).foregroundStyle(Theme.secondaryText) }
                    }
                }
                .glassCard()

                HStack(spacing: 12) {
                    Button { Task { await account.refresh() } } label: { Label("Refresh profile", systemImage: "arrow.clockwise") }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(account.state == .signingIn)
                    Button(role: .destructive) { account.signOut() } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Application (client) ID").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                    TextField("00000000-0000-0000-0000-000000000000", text: $clientID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(12).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.graphite.opacity(0.7)))
                        .foregroundStyle(.white)
                    Text("Register a free app at entra.microsoft.com (account type: personal Microsoft accounts), add a Mobile and desktop redirect URI of \(AccountManager.redirectURI), and allow public client flows. The client ID isn't a secret. AETHER never stores or needs a client secret.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                .glassCard()

                Button { Haptics.tap(); Task { await account.signIn() } } label: {
                    Label(account.state == .signingIn ? "Signing in..." : "Sign in with Microsoft", systemImage: "person.badge.key.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(account.state == .signingIn || clientID.nilIfEmpty == nil)
            }

            if case .failed(let message) = account.state {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.warning)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What this does").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                BulletList(lines: [
                    "Signing in proves who you are on Xbox Live and shows your gamertag.",
                    "It does not check that you own Minecraft, and it doesn't sign Minecraft in. Minecraft keeps its own sign-in.",
                    "Only a refresh token is kept, in the device Keychain. Signing out deletes it."
                ])
            }
            .glassCard()
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
