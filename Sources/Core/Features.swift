import SwiftUI

enum FeatureStatus: String {
    case supported
    case experimental
    case requiresRuntime

    var title: String {
        switch self {
        case .supported: return "Supported"
        case .experimental: return "Experimental"
        case .requiresRuntime: return "Requires runtime integration"
        }
    }

    var symbol: String {
        switch self {
        case .supported: return "checkmark.seal.fill"
        case .experimental: return "flask.fill"
        case .requiresRuntime: return "lock.fill"
        }
    }

    var color: Color {
        switch self {
        case .supported: return Theme.accent
        case .experimental: return Theme.warning
        case .requiresRuntime: return Color(red: 0.95, green: 0.45, blue: 0.40)
        }
    }
}

enum FeatureOptionKind {
    case toggle(Bool)
    case slider(range: ClosedRange<Double>, step: Double, defaultValue: Double, unit: String)
    case choice([String], defaultValue: String)
}

struct FeatureOption: Identifiable {
    let id: String
    let title: String
    let kind: FeatureOptionKind
}

struct FeatureDescriptor: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let summary: String
    let status: FeatureStatus
    let platforms: String
    let requirement: String
    let options: [FeatureOption]
}

/// Catalog and persistence for AETHER's built-in client features.
/// Settings persist in UserDefaults under `feature.<id>.<option>`.
/// Every in-game feature is `requiresRuntime`: configuration is stored, but nothing can act on
/// Minecraft until a legitimate runtime integration exists (see docs/TECHNICAL_REPORT.md).
final class FeatureManager: ObservableObject {
    static let runtimeNote = "Needs code running inside Minecraft's process. iOS doesn't allow that for a separate app, so this setting is stored but has no effect on gameplay yet."

    static let catalog: [FeatureDescriptor] = [
        FeatureDescriptor(
            id: "zoom", name: "Camera Zoom", symbol: "camera.fill",
            summary: "A floating button inside Minecraft that magnifies the screen and restores it on a second tap.",
            status: .experimental, platforms: "iPhone, iPad (touch)",
            requirement: "Patch your own Minecraft IPA with Patch Studio. It's a screen magnification, not a field-of-view change, and it hasn't been tested on a device yet.",
            options: [
                FeatureOption(id: "strength", title: "Zoom strength", kind: .slider(range: 1.5...8, step: 0.5, defaultValue: 3, unit: "x")),
                FeatureOption(id: "buttonSize", title: "Button size", kind: .slider(range: 36...80, step: 2, defaultValue: 54, unit: "pt")),
                FeatureOption(id: "opacity", title: "Button opacity", kind: .slider(range: 0.3...1, step: 0.05, defaultValue: 0.9, unit: "")),
                FeatureOption(id: "smooth", title: "Smooth transition", kind: .toggle(true)),
                FeatureOption(id: "keyboard", title: "Keyboard shortcut (Z)", kind: .toggle(true))
            ]),
        FeatureDescriptor(
            id: "crosshair", name: "Custom Crosshair", symbol: "scope",
            summary: "Replaces the crosshair with your own style, size and colour.",
            status: .requiresRuntime, platforms: "iPhone, iPad",
            requirement: "Drawing into Minecraft's HUD.",
            options: [
                FeatureOption(id: "style", title: "Style", kind: .choice(["Cross", "Dot", "Circle"], defaultValue: "Cross")),
                FeatureOption(id: "size", title: "Size", kind: .slider(range: 6...40, step: 1, defaultValue: 16, unit: "pt")),
                FeatureOption(id: "color", title: "Colour", kind: .choice(["White", "Green", "Red", "Yellow"], defaultValue: "White")),
                FeatureOption(id: "opacity", title: "Opacity", kind: .slider(range: 0.2...1, step: 0.05, defaultValue: 0.9, unit: ""))
            ]),
        FeatureDescriptor(
            id: "fps", name: "FPS Counter", symbol: "speedometer",
            summary: "Shows the game's frame rate on screen.",
            status: .requiresRuntime, platforms: "iPhone, iPad",
            requirement: "Reading Minecraft's frame timing. AETHER can't measure another app's frames.",
            options: [
                FeatureOption(id: "position", title: "Position", kind: .choice(["Top left", "Top right", "Bottom left", "Bottom right"], defaultValue: "Top left")),
                FeatureOption(id: "interval", title: "Update interval", kind: .slider(range: 0.25...2, step: 0.25, defaultValue: 0.5, unit: "s"))
            ]),
        FeatureDescriptor(
            id: "coordinates", name: "Coordinates HUD", symbol: "location.north.line.fill",
            summary: "Shows your position and facing direction.",
            status: .requiresRuntime, platforms: "iPhone, iPad",
            requirement: "Reading the player's position from the running game.",
            options: [
                FeatureOption(id: "position", title: "Position", kind: .choice(["Top left", "Top right", "Bottom left", "Bottom right"], defaultValue: "Top left")),
                FeatureOption(id: "direction", title: "Show direction", kind: .toggle(true)),
                FeatureOption(id: "decimals", title: "Decimals", kind: .slider(range: 0...3, step: 1, defaultValue: 0, unit: ""))
            ]),
        FeatureDescriptor(
            id: "keystrokes", name: "Keystrokes Display", symbol: "keyboard.fill",
            summary: "Shows the keys and buttons you press.",
            status: .requiresRuntime, platforms: "iPad with keyboard or mouse; controllers",
            requirement: "Seeing the input Minecraft receives, which is only possible inside its process.",
            options: [
                FeatureOption(id: "layout", title: "Layout", kind: .choice(["WASD", "WASD + space", "Compact"], defaultValue: "WASD")),
                FeatureOption(id: "mouse", title: "Show mouse buttons", kind: .toggle(true)),
                FeatureOption(id: "scale", title: "Scale", kind: .slider(range: 0.6...1.6, step: 0.1, defaultValue: 1, unit: "x"))
            ]),
        FeatureDescriptor(
            id: "hud", name: "Customizable HUD", symbol: "rectangle.3.group.fill",
            summary: "Lets you move and resize every AETHER HUD element.",
            status: .requiresRuntime, platforms: "iPhone, iPad",
            requirement: "A HUD layer inside the game view.",
            options: [
                FeatureOption(id: "scale", title: "Global scale", kind: .slider(range: 0.6...1.6, step: 0.1, defaultValue: 1, unit: "x")),
                FeatureOption(id: "opacity", title: "Global opacity", kind: .slider(range: 0.3...1, step: 0.05, defaultValue: 0.9, unit: "")),
                FeatureOption(id: "snap", title: "Snap to grid", kind: .toggle(true))
            ]),
        FeatureDescriptor(
            id: "sprint", name: "Toggle Sprint", symbol: "figure.run",
            summary: "Keeps sprint on without holding the control.",
            status: .requiresRuntime, platforms: "iPhone, iPad, controllers",
            requirement: "Sending input to Minecraft.",
            options: [
                FeatureOption(id: "mode", title: "Activation", kind: .choice(["Tap to toggle", "Double tap forward"], defaultValue: "Tap to toggle")),
                FeatureOption(id: "indicator", title: "Show indicator", kind: .toggle(true))
            ]),
        FeatureDescriptor(
            id: "controls", name: "Custom Mobile Controls", symbol: "gamecontroller.fill",
            summary: "Rearranges and resizes the on-screen touch controls.",
            status: .requiresRuntime, platforms: "iPhone, iPad",
            requirement: "Replacing Minecraft's touch layer.",
            options: [
                FeatureOption(id: "scale", title: "Control scale", kind: .slider(range: 0.6...1.6, step: 0.1, defaultValue: 1, unit: "x")),
                FeatureOption(id: "opacity", title: "Control opacity", kind: .slider(range: 0.2...1, step: 0.05, defaultValue: 0.7, unit: "")),
                FeatureOption(id: "leftHanded", title: "Left-handed layout", kind: .toggle(false))
            ]),
        FeatureDescriptor(
            id: "performance", name: "Performance Information", symbol: "gauge.with.dots.needle.67percent",
            summary: "Shows frame time, memory use and thermal state for the game.",
            status: .requiresRuntime, platforms: "iPhone, iPad",
            requirement: "Measuring the Minecraft process. AETHER can only measure itself.",
            options: [
                FeatureOption(id: "frameTime", title: "Frame time", kind: .toggle(true)),
                FeatureOption(id: "memory", title: "Memory", kind: .toggle(true)),
                FeatureOption(id: "thermal", title: "Thermal state", kind: .toggle(false))
            ]),
        FeatureDescriptor(
            id: "clientSettings", name: "Custom Client Settings", symbol: "slider.horizontal.3",
            summary: "Applies a saved profile of client options when a game starts.",
            status: .requiresRuntime, platforms: "iPhone, iPad",
            requirement: "Writing options into a running Minecraft.",
            options: [
                FeatureOption(id: "profile", title: "Profile", kind: .choice(["Default", "Performance", "Quality"], defaultValue: "Default")),
                FeatureOption(id: "applyOnLaunch", title: "Apply on launch", kind: .toggle(true))
            ])
    ]

    static func descriptor(_ id: String) -> FeatureDescriptor? { catalog.first { $0.id == id } }

    private let defaults = UserDefaults.standard

    private func key(_ feature: String, _ option: String) -> String { "feature.\(feature).\(option)" }

    func isEnabled(_ feature: String) -> Bool { defaults.bool(forKey: key(feature, "enabled")) }

    func setEnabled(_ feature: String, _ value: Bool) {
        objectWillChange.send()
        defaults.set(value, forKey: key(feature, "enabled"))
    }

    func bool(_ feature: String, _ option: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key(feature, option)) as? Bool ?? fallback
    }

    func double(_ feature: String, _ option: String, default fallback: Double) -> Double {
        defaults.object(forKey: key(feature, option)) as? Double ?? fallback
    }

    func string(_ feature: String, _ option: String, default fallback: String) -> String {
        defaults.string(forKey: key(feature, option)) ?? fallback
    }

    func set(_ value: Any, _ feature: String, _ option: String) {
        objectWillChange.send()
        defaults.set(value, forKey: key(feature, option))
    }

    func reset(_ feature: String) {
        objectWillChange.send()
        guard let descriptor = Self.descriptor(feature) else { return }
        for option in descriptor.options { defaults.removeObject(forKey: key(feature, option.id)) }
        defaults.removeObject(forKey: key(feature, "posX"))
        defaults.removeObject(forKey: key(feature, "posY"))
    }

    func binding(_ feature: String, _ option: FeatureOption) -> Binding<Double> {
        guard case .slider(_, _, let fallback, _) = option.kind else { return .constant(0) }
        return Binding(get: { self.double(feature, option.id, default: fallback) },
                       set: { self.set($0, feature, option.id) })
    }

    func boolBinding(_ feature: String, _ option: FeatureOption) -> Binding<Bool> {
        guard case .toggle(let fallback) = option.kind else { return .constant(false) }
        return Binding(get: { self.bool(feature, option.id, default: fallback) },
                       set: { self.set($0, feature, option.id) })
    }

    func choiceBinding(_ feature: String, _ option: FeatureOption) -> Binding<String> {
        guard case .choice(_, let fallback) = option.kind else { return .constant("") }
        return Binding(get: { self.string(feature, option.id, default: fallback) },
                       set: { self.set($0, feature, option.id) })
    }
}
