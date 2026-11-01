import AppKit
import IslandCore
import IslandDesign
import SwiftUI

struct AppearanceSettingsPane: View {
    let settings: SettingsStore

    private var appearance: AppearanceSettings { settings.settings.appearance }

    var body: some View {
        Form {
            Section {
                IslandPreview(appearance: appearance, animation: settings.settings.animation)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            Section("Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(ThemePreset.allCases) { preset in
                        ThemeCard(preset: preset, values: preset == .custom ? appearance.custom : preset.values,
                                  isSelected: appearance.preset == preset) {
                            settings.update {
                                if preset == .custom {
                                    $0.appearance.beginCustomizing()
                                } else {
                                    $0.appearance.preset = preset
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                if appearance.preset == .liquidGlass, ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 {
                    SettingsNote("Liquid Glass uses the system material on macOS 26 and later; an equivalent blur is used here.")
                }
                if appearance.preset != .custom {
                    Button("Customize This Theme…") { settings.update { $0.appearance.beginCustomizing() } }
                }
            }

            if appearance.preset == .custom {
                customThemeSection
            }

            layoutSection
        }
        .formStyle(.grouped)
    }

    private var customThemeSection: some View {
        Section("Custom Theme") {
            ColorPicker("Background", selection: colorBinding(\.appearance.custom.background), supportsOpacity: false)
            ValueSlider(title: "Opacity", value: settings.binding(\.appearance.custom.backgroundOpacity), range: 0...1, format: SettingsFormat.percent)
            Picker("Blur material", selection: settings.binding(\.appearance.custom.material)) {
                ForEach(BlurMaterial.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            ColorPicker("Border", selection: colorBinding(\.appearance.custom.borderColor), supportsOpacity: true)
            ValueSlider(title: "Border width", value: settings.binding(\.appearance.custom.borderWidth), range: 0...3, step: 0.25, format: { String(format: "%.2f pt", $0) })
            ValueSlider(title: "Shadow", value: settings.binding(\.appearance.custom.shadowOpacity), range: 0...1, format: SettingsFormat.percent)
            ValueSlider(title: "Shadow radius", value: settings.binding(\.appearance.custom.shadowRadius), range: 0...30, step: 1, format: SettingsFormat.points)
            Picker("Text", selection: settings.binding(\.appearance.custom.foreground)) {
                ForEach(ForegroundTone.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            ColorPicker("Accent", selection: colorBinding(\.appearance.custom.accent), supportsOpacity: false)
            Picker("Typeface", selection: settings.binding(\.appearance.custom.fontDesign)) {
                ForEach(FontDesignOption.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            ValueSlider(title: "Text size", value: settings.binding(\.appearance.custom.fontScale), range: 0.8...1.4, step: 0.05, format: SettingsFormat.multiplier)
        }
    }

    private var layoutSection: some View {
        Section("Size and Shape") {
            ValueSlider(title: "Expanded width", value: settings.binding(\.appearance.layout.expandedWidth), range: LayoutSettings.expandedWidthRange, step: 10, format: SettingsFormat.points)
            ValueSlider(title: "Expanded height", value: settings.binding(\.appearance.layout.expandedHeight), range: LayoutSettings.expandedHeightRange, step: 10, format: SettingsFormat.points)
            ValueSlider(title: "Corner radius", value: settings.binding(\.appearance.layout.cornerRadius), range: LayoutSettings.cornerRadiusRange, step: 1, format: SettingsFormat.points)
            ValueSlider(title: "Compact corner radius", value: settings.binding(\.appearance.layout.compactCornerRadius), range: 0...20, step: 1, format: SettingsFormat.points)
            ValueSlider(title: "Padding", value: settings.binding(\.appearance.layout.padding), range: 6...28, step: 1, format: SettingsFormat.points)
            ValueSlider(title: "Icon size", value: settings.binding(\.appearance.layout.iconSize), range: 11...22, step: 1, format: SettingsFormat.points)
            ValueSlider(title: "Live activity width", value: settings.binding(\.appearance.layout.wingWidth), range: 48...120, step: 2, format: SettingsFormat.points)
            ValueSlider(title: "Virtual island width", value: settings.binding(\.appearance.layout.virtualWidth), range: 120...320, step: 10, format: SettingsFormat.points)
            ValueSlider(title: "Virtual island height", value: settings.binding(\.appearance.layout.virtualHeight), range: 24...44, step: 1, format: SettingsFormat.points)
            SettingsNote("On a MacBook with a notch, the compact island always matches the notch exactly.")
        }
    }

    private func colorBinding(_ keyPath: WritableKeyPath<AppSettings, RGBAColor>) -> Binding<Color> {
        Binding(
            get: { Color(settings.settings[keyPath: keyPath]) },
            set: { color in settings.update { $0[keyPath: keyPath] = RGBAColor(color) } }
        )
    }
}

private struct ThemeCard: View {
    let preset: ThemePreset
    let values: ThemeValues
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    LinearGradient(colors: [.blue.opacity(0.55), .purple.opacity(0.45), .orange.opacity(0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    IslandSurface(shape: IslandShape(bottomRadius: 9, earRadius: 3), showsShadow: true)
                        .frame(width: 70, height: 22)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .environment(\.islandTheme, IslandTheme(values: values))
                }
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : .secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1))
                Text(preset.displayName).font(.caption)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A live, non-interactive island rendered with the current appearance and animation settings.
struct IslandPreview: View {
    let appearance: AppearanceSettings
    let animation: AnimationSettings
    var expanded = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let theme = IslandTheme(appearance)
        let layout = appearance.layout
        let scale = 0.62
        let width = (expanded ? layout.expandedWidth : 200) * scale
        let height = (expanded ? layout.expandedHeight : 32) * scale
        let radius = (expanded ? layout.cornerRadius : layout.compactCornerRadius) * scale

        ZStack(alignment: .top) {
            LinearGradient(colors: [.indigo.opacity(0.6), .teal.opacity(0.5), .pink.opacity(0.4)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack {
                IslandSurface(shape: IslandShape(bottomRadius: radius, earRadius: 4), showsShadow: expanded)
                if expanded {
                    HStack(spacing: 10) {
                        ProgressRing(progress: 0.62, lineWidth: 4).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Focus").font(theme.headlineFont).foregroundStyle(theme.primary)
                            Text("14:32 remaining").font(theme.captionFont).foregroundStyle(theme.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .transition(.opacity)
                }
            }
            .frame(width: width, height: height)
        }
        .frame(width: 360, height: max(150, height + 30))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .environment(\.islandTheme, theme)
        .animation(IslandAnimations(settings: animation, reduceMotion: reduceMotion).expand, value: expanded)
        .accessibilityHidden(true)
    }
}

struct AnimationSettingsPane: View {
    let settings: SettingsStore

    @State private var previewExpanded = true

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    IslandPreview(appearance: settings.settings.appearance, animation: settings.settings.animation, expanded: previewExpanded)
                    Button(previewExpanded ? "Collapse Preview" : "Expand Preview") { previewExpanded.toggle() }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Motion") {
                Picker("Style", selection: settings.binding(\.animation.style)) {
                    ForEach(AnimationStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                ValueSlider(title: "Speed", value: settings.binding(\.animation.speed), range: AnimationSettings.speedRange, step: 0.05, format: SettingsFormat.multiplier)
                Picker("Content transition", selection: settings.binding(\.animation.contentTransition)) {
                    ForEach(ContentTransitionStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }

            Section("Details") {
                Toggle("Animate the media playing indicator", isOn: settings.binding(\.animation.animateMediaIndicator))
                Toggle("Animate album artwork changes", isOn: settings.binding(\.animation.artworkTransitions))
            }

            Section {
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    Label("Reduce Motion is on. IslandBar uses short cross-fades instead of the animations above.", systemImage: "figure.walk.motion")
                        .foregroundStyle(.secondary)
                } else {
                    SettingsNote("IslandBar follows System Settings › Accessibility › Display › Reduce Motion.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
