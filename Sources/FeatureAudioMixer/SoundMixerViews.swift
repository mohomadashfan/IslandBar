import AppKit
import IslandCore
import IslandDesign
import SwiftUI

struct SoundMixerView: View {
    let module: SoundMixerModule

    private enum Page: Hashable { case apps, equalizer }
    @State private var page = Page.apps
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                pageButton("Apps", .apps)
                pageButton("Equalizer", .equalizer)
                Spacer()
                if page == .equalizer {
                    presetMenu
                    IslandPillButton(module.settings.equalizerEnabled ? "On" : "Off", symbol: "power") {
                        module.setEqualizerEnabled(!module.settings.equalizerEnabled)
                    }
                } else if !module.settings.appVolumes.isEmpty || !module.settings.mutedApps.isEmpty {
                    IslandPillButton("Reset", symbol: "arrow.counterclockwise") { module.resetApps() }
                }
            }
            if let error = module.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(theme.font(10)).foregroundStyle(theme.secondary).lineLimit(2)
                    Spacer(minLength: 0)
                    IslandPillButton("Settings…") { SoundMixerModule.openPrivacySettings() }
                }
            }
            switch page {
            case .apps: appList
            case .equalizer: EqualizerView(module: module)
            }
        }
    }

    private func pageButton(_ title: String, _ target: Page) -> some View {
        Button(title) { page = target }
            .buttonStyle(.plain)
            .font(theme.font(11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(page == target ? theme.primary.opacity(0.16) : .clear))
            .foregroundStyle(page == target ? theme.primary : theme.secondary)
    }

    private var presetMenu: some View {
        Menu {
            ForEach(EqualizerPreset.allCases) { preset in
                Button(preset.displayName) { module.selectPreset(preset) }
            }
        } label: {
            Text(module.settings.equalizerPreset.displayName)
                .font(theme.font(11, weight: .medium))
                .foregroundStyle(theme.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var appList: some View {
        if !module.isSupported {
            IslandEmptyState(symbol: "speaker.slash", title: "Not available", message: "Per-app volume needs macOS 14.2 or later.")
        } else if module.apps.isEmpty {
            IslandEmptyState(symbol: "speaker.wave.2", title: "Nothing is playing", message: "Apps appear here while they play audio.")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(module.apps) { app in
                        AppVolumeRow(module: module, app: app)
                    }
                }
            }
        }
    }
}

private struct AppVolumeRow: View {
    let module: SoundMixerModule
    let app: AudioAppGroup

    @Environment(\.islandTheme) private var theme

    var body: some View {
        let muted = module.isMuted(app)
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .opacity(app.isPlaying ? 1 : 0.5)
            Text(app.name)
                .font(theme.font(11, weight: .medium))
                .foregroundStyle(theme.primary)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)
            Slider(
                value: Binding(get: { module.volume(for: app) }, set: { module.setVolume($0, for: app) }),
                in: SoundMixerSettings.volumeRange
            )
            .controlSize(.mini)
            .tint(module.volume(for: app) > 1 ? .orange : theme.accent)
            Text(muted ? "Muted" : "\(Int((module.volume(for: app) * 100).rounded()))%")
                .font(theme.monospacedDigits(10))
                .foregroundStyle(theme.secondary)
                .frame(width: 40, alignment: .trailing)
            IslandIconButton(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 10, help: muted ? "Unmute \(app.name)" : "Mute \(app.name)") {
                module.toggleMute(app)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.name)
    }

    private var icon: NSImage {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.id).first?.icon
            ?? NSWorkspace.shared.icon(for: .application)
    }
}

private struct EqualizerView: View {
    let module: SoundMixerModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        let gains = module.settings.activeGains
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<SoundMixerSettings.bandCount, id: \.self) { band in
                VStack(spacing: 4) {
                    Text(String(format: "%+.0f", gains[band]))
                        .font(theme.monospacedDigits(9))
                        .foregroundStyle(theme.secondary)
                    VerticalGainSlider(value: gains[band]) { module.setGain($0, band: band) }
                    Text(Equalizer.bandLabels[band])
                        .font(theme.font(9, weight: .medium))
                        .foregroundStyle(theme.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .opacity(module.settings.equalizerEnabled ? 1 : 0.45)
    }
}

/// Drag up or down to set a band's gain; double-click to reset it to 0 dB.
private struct VerticalGainSlider: View {
    let value: Double
    let onChange: (Double) -> Void

    @Environment(\.islandTheme) private var theme
    private let range = SoundMixerSettings.gainRange

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbY = height * (1 - fraction)
            ZStack(alignment: .top) {
                Capsule().fill(theme.fill).frame(width: 4)
                Rectangle().fill(theme.tertiary).frame(width: 10, height: 1).offset(y: height / 2)
                Capsule()
                    .fill(theme.accent)
                    .frame(width: 4, height: abs(thumbY - height / 2))
                    .offset(y: min(thumbY, height / 2))
                Circle()
                    .fill(theme.primary)
                    .frame(width: 12, height: 12)
                    .offset(y: thumbY - 6)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let position = min(max(drag.location.y / max(height, 1), 0), 1)
                    let gain = range.upperBound - position * (range.upperBound - range.lowerBound)
                    onChange((gain * 2).rounded() / 2)
                }
            )
            .onTapGesture(count: 2) { onChange(0) }
        }
        .frame(minHeight: 70)
        .accessibilityElement()
        .accessibilityValue(String(format: "%+.1f decibels", value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 1, range.upperBound))
            case .decrement: onChange(max(value - 1, range.lowerBound))
            @unknown default: break
            }
        }
    }
}
