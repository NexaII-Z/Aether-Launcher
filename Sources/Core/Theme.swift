import SwiftUI

enum SettingsKey {
    static let haptics = "aether.haptics"
    static let confirmLaunch = "aether.confirmLaunch"
    static let autoRefresh = "aether.autoRefresh"
    static let solidCards = "aether.solidCards"
}

enum Theme {
    static let ink = Color(red: 0.030, green: 0.035, blue: 0.040)
    static let graphite = Color(red: 0.080, green: 0.090, blue: 0.098)
    static let accent = Color(red: 0.310, green: 0.830, blue: 0.380)
    static let accentDeep = Color(red: 0.120, green: 0.450, blue: 0.220)
    static let warning = Color(red: 0.980, green: 0.700, blue: 0.250)
    static let hairline = Color.white.opacity(0.10)
    static let secondaryText = Color.white.opacity(0.62)
}

struct AetherBackground: View {
    var body: some View {
        ZStack {
            Theme.ink
            RadialGradient(colors: [Theme.accentDeep.opacity(0.55), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.accent.opacity(0.10), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 420)
        }
    }
}

extension View {
    func aetherScreen() -> some View {
        background(AetherBackground().ignoresSafeArea())
    }

    func glassCard(radius: CGFloat = 24, padding: CGFloat = 18) -> some View {
        modifier(GlassCard(radius: radius, padding: padding))
    }
}

private struct GlassCard: ViewModifier {
    @AppStorage(SettingsKey.solidCards) private var solidCards = false
    let radius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { surface }
    }

    @ViewBuilder
    private var surface: some View {
        if solidCards {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.graphite)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        } else {
            glassOrMaterial
        }
    }

    @ViewBuilder
    private var glassOrMaterial: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            materialSurface
        }
        #else
        materialSurface
        #endif
    }

    private var materialSurface: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.graphite.opacity(0.55))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(Color.black.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Color(red: 0.22, green: 0.70, blue: 0.33)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Theme.accent.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

@MainActor
enum Haptics {
    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.haptics) as? Bool ?? true
    }

    static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func failure() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
