import SwiftUI

struct ClientView: View {
    @EnvironmentObject private var features: FeatureManager

    var body: some View {
        Screen {
            ScreenHeader(title: "Client", subtitle: "AETHER's built-in features")

            VStack(alignment: .leading, spacing: 10) {
                Label("Zoom button inside Minecraft", systemImage: "camera.fill")
                    .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                Text("AETHER can't run or draw inside Minecraft itself. The zoom button is added to your own Minecraft IPA with Patch Studio. Other features below still need a runtime that doesn't exist on stock iOS.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                HStack(spacing: 12) {
                    NavigationLink { PatchStudioView() } label: { Label("Patch Studio", systemImage: "wand.and.stars") }
                        .buttonStyle(PrimaryButtonStyle())
                    NavigationLink { ZoomPrototypeView() } label: { Label("Preview", systemImage: "camera.fill") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                NavigationLink { RuntimeInvestigationView() } label: { Label("Investigation", systemImage: "doc.text.magnifyingglass") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .glassCard()

            ForEach(FeatureManager.catalog) { feature in
                NavigationLink { FeatureDetailView(featureID: feature.id) } label: { card(feature) }
                    .buttonStyle(.plain)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func card(_ feature: FeatureDescriptor) -> some View {
        HStack(spacing: 14) {
            Image(systemName: feature.symbol)
                .font(.title3).foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.name).font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                StatusBadge(status: feature.status)
            }
            Spacer(minLength: 8)
            Text(features.isEnabled(feature.id) ? "Saved on" : "Off")
                .font(.caption).foregroundStyle(Theme.secondaryText)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
        }
        .glassCard(radius: 22, padding: 14)
    }
}

struct StatusBadge: View {
    let status: FeatureStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(status.color.opacity(0.14)))
    }
}

struct FeatureDetailView: View {
    @EnvironmentObject private var features: FeatureManager
    let featureID: String

    var body: some View {
        if let feature = FeatureManager.descriptor(featureID) {
            Screen {
                HStack(spacing: 12) {
                    Image(systemName: feature.symbol).font(.title).foregroundStyle(Theme.accent)
                    Text(feature.name).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                }
                StatusBadge(status: feature.status)
                Text(feature.summary).font(.subheadline).foregroundStyle(.white.opacity(0.86))

                VStack(alignment: .leading, spacing: 10) {
                    InfoRow(label: "Platforms", value: feature.platforms)
                    Divider().overlay(Theme.hairline)
                    InfoRow(label: "Needs", value: feature.requirement)
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(get: { features.isEnabled(feature.id) },
                                         set: { features.setEnabled(feature.id, $0) })) {
                        Text("Enable for when a runtime exists")
                            .font(.system(.body, design: .rounded).weight(.medium)).foregroundStyle(.white)
                    }
                    .tint(Theme.accent)
                    if feature.status == .requiresRuntime {
                        Text("Saved only. It has no effect on Minecraft today.")
                            .font(.footnote).foregroundStyle(Theme.warning)
                    }
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Settings").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                    ForEach(feature.options) { option in optionRow(feature.id, option) }
                }
                .glassCard()

                if feature.id == "zoom" {
                    NavigationLink { ZoomPrototypeView() } label: { Label("Open the overlay prototype", systemImage: "camera.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                }

                Button(role: .destructive) { features.reset(feature.id) } label: {
                    Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .navigationTitle(feature.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func optionRow(_ feature: String, _ option: FeatureOption) -> some View {
        switch option.kind {
        case .toggle:
            Toggle(option.title, isOn: features.boolBinding(feature, option)).tint(Theme.accent).foregroundStyle(.white)
        case .slider(let range, let step, _, let unit):
            let binding = features.binding(feature, option)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(option.title).foregroundStyle(.white)
                    Spacer()
                    Text(String(format: "%g", binding.wrappedValue) + (unit.isEmpty ? "" : " \(unit)"))
                        .foregroundStyle(Theme.secondaryText)
                }
                Slider(value: binding, in: range, step: step).tint(Theme.accent)
            }
        case .choice(let choices, _):
            Picker(option.title, selection: features.choiceBinding(feature, option)) {
                ForEach(choices, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Zoom overlay prototype

struct ZoomPrototypeView: View {
    @EnvironmentObject private var features: FeatureManager
    @EnvironmentObject private var zoom: ZoomController

    var body: some View {
        Screen {
            Text("Overlay prototype")
                .font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            StatusBadge(status: .experimental)

            Text("This tests the floating button itself: dragging, tapping, size, strength and the keyboard shortcut. The stage is a plain test canvas, not Minecraft, and nothing on it is scaled to imitate a zoom.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)

            GeometryReader { proxy in
                ZStack {
                    StageGrid()
                    Text("Test stage")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(10)
                    ZoomOverlayButton(stage: proxy.size)
                }
                .coordinateSpace(name: "stage")
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            }
            .frame(height: 300)

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Requested", value: zoom.requested ? "Zoomed in" : "Normal")
                Divider().overlay(Theme.hairline)
                InfoRow(label: "Applied to a real camera", value: zoom.applied ? "Yes" : "No")
                Divider().overlay(Theme.hairline)
                InfoRow(label: "Camera backend", value: zoom.backendAvailable ? "Available" : "Unavailable")
                if !zoom.backendAvailable {
                    Text(zoom.backendReason).font(.footnote).foregroundStyle(Theme.warning)
                }
                if let message = zoom.message {
                    Text(message).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            .glassCard()

            if let feature = FeatureManager.descriptor("zoom") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(feature.options) { option in
                        switch option.kind {
                        case .slider(let range, let step, _, let unit):
                            let binding = features.binding("zoom", option)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(option.title).foregroundStyle(.white)
                                    Spacer()
                                    Text(String(format: "%g", binding.wrappedValue) + (unit.isEmpty ? "" : " \(unit)"))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                Slider(value: binding, in: range, step: step).tint(Theme.accent)
                            }
                        case .toggle:
                            Toggle(option.title, isOn: features.boolBinding("zoom", option)).tint(Theme.accent).foregroundStyle(.white)
                        case .choice:
                            EmptyView()
                        }
                    }
                }
                .glassCard()
            }

            HStack(spacing: 12) {
                Button {
                    features.set(0.88, "zoom", "posX")
                    features.set(0.25, "zoom", "posY")
                } label: { Label("Reset position", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { zoom.reset() } label: { Label("Reset zoom", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .navigationTitle("Zoom prototype")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private struct StageGrid: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.06, green: 0.07, blue: 0.08)))
            var path = Path()
            let spacing: CGFloat = 28
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
            context.stroke(path, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
        }
    }
}

/// The floating camera button. Position is stored as fractions of the stage so it survives rotation and resizing.
struct ZoomOverlayButton: View {
    @EnvironmentObject private var features: FeatureManager
    @EnvironmentObject private var zoom: ZoomController
    let stage: CGSize

    var body: some View {
        let size = features.double("zoom", "buttonSize", default: 54)
        let opacity = features.double("zoom", "opacity", default: 0.9)
        let fractionX = features.double("zoom", "posX", default: 0.88)
        let fractionY = features.double("zoom", "posY", default: 0.25)
        let center = CGPoint(x: fractionX * stage.width, y: fractionY * stage.height)

        ZStack {
            if features.bool("zoom", "keyboard", default: true) {
                Button("Toggle zoom") { toggle() }
                    .keyboardShortcut("z", modifiers: [])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            Image(systemName: zoom.requested ? "camera.viewfinder" : "camera.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(zoom.requested ? Color.black.opacity(0.85) : Theme.accent)
                .frame(width: size, height: size)
                .background(Circle().fill(zoom.requested ? Theme.accent : Theme.graphite.opacity(0.85)))
                .overlay(Circle().strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1.5))
                .opacity(opacity)
                .contentShape(Circle())
                .hoverEffect(.lift)
                .onTapGesture { toggle() }
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named("stage"))
                        .onChanged { value in
                            guard stage.width > 0, stage.height > 0 else { return }
                            let half = size / 2
                            let x = min(max(value.location.x, half), stage.width - half)
                            let y = min(max(value.location.y, half), stage.height - half)
                            features.set(Double(x / stage.width), "zoom", "posX")
                            features.set(Double(y / stage.height), "zoom", "posY")
                        }
                )
                .accessibilityLabel("Camera zoom")
                .accessibilityValue(zoom.requested ? "Zoomed in" : "Normal")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggle() }
        }
        .position(center)
    }

    private func toggle() {
        Haptics.tap()
        zoom.toggle(strength: features.double("zoom", "strength", default: 3))
    }
}
