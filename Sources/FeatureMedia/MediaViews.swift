import IslandDesign
import SwiftUI

private func formatTime(_ interval: TimeInterval) -> String {
    let total = max(Int(interval), 0)
    return String(format: "%d:%02d", total / 60, total % 60)
}

private struct ArtworkView: View {
    let image: NSImage?
    let trackID: String?
    let size: CGFloat
    let cornerRadius: CGFloat
    var glow: NSColor? = nil

    @Environment(\.islandTheme) private var theme
    @Environment(\.islandAnimations) private var animations

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient(colors: [theme.accent.opacity(0.55), theme.accent.opacity(0.15)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(animations.artwork == nil ? .identity : .opacity.combined(with: .scale(scale: 0.94)))
                    .id(trackID)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: Color(nsColor: glow ?? .clear).opacity(size > 40 ? 0.55 : 0), radius: 18, y: 4)
        .animation(animations.artwork, value: trackID)
    }
}

struct MediaCompactLeading: View {
    let module: MediaModule

    var body: some View {
        ArtworkView(image: module.artwork, trackID: module.nowPlaying?.trackID, size: 20, cornerRadius: 5)
            .accessibilityLabel(module.nowPlaying?.title ?? "Media")
    }
}

struct MediaCompactTrailing: View {
    let module: MediaModule

    @Environment(\.islandTheme) private var theme
    @Environment(\.islandAnimations) private var animations

    var body: some View {
        let playing = module.nowPlaying?.isPlaying == true
        Image(systemName: "waveform")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.accent)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: playing && animations.animatesIndicators)
            .accessibilityLabel(playing ? "Playing" : "Paused")
    }
}

struct MediaExpandedView: View {
    let module: MediaModule

    @Environment(\.islandTheme) private var theme

    var body: some View {
        if let track = module.nowPlaying {
            HStack(spacing: theme.padding) {
                ArtworkView(image: module.artwork, trackID: track.trackID, size: 92, cornerRadius: 14, glow: module.artworkAccent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(theme.titleFont)
                        .foregroundStyle(theme.primary)
                        .lineLimit(1)
                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)

                    MediaProgress(track: track, tint: module.artworkAccent.map { Color(nsColor: $0) })
                        .padding(.top, 4)

                    HStack(spacing: 6) {
                        IslandIconButton("backward.fill", size: 13, help: "Previous track") { module.send(.previous) }
                        IslandIconButton(track.isPlaying ? "pause.fill" : "play.fill", size: 16, prominent: true,
                                         help: track.isPlaying ? "Pause" : "Play") { module.send(.playPause) }
                        IslandIconButton("forward.fill", size: 13, help: "Next track") { module.send(.next) }
                        Spacer()
                        Text(track.sourceDescription)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.tertiary)
                            .lineLimit(1)
                    }
                    permissionHint
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        } else {
            VStack(spacing: 8) {
                IslandEmptyState(
                    symbol: "music.note",
                    title: "Nothing playing",
                    message: "Start playback in Music or Spotify, or turn on browsers in Settings › Media."
                )
                permissionHint
            }
        }
    }

    @ViewBuilder
    private var permissionHint: some View {
        switch module.setupHint {
        case .allowAutomation(let player):
            IslandPillButton("Allow access to \(player.displayName)", symbol: "lock.open") {
                module.requestPermission(for: player)
            }
        case .enableJavaScript(let player):
            Label("In \(player.displayName), turn on \(player.javaScriptSettingLocation ?? "Allow JavaScript from Apple Events")",
                  systemImage: "info.circle")
                .font(theme.font(10))
                .foregroundStyle(theme.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        case nil:
            EmptyView()
        }
    }
}

private struct MediaProgress: View {
    let track: NowPlaying
    var tint: Color?

    @Environment(\.islandTheme) private var theme

    var body: some View {
        if let duration = track.duration {
            Group {
                if track.isPlaying {
                    TimelineView(.periodic(from: .now, by: 1)) { context in bar(at: context.date, duration: duration) }
                } else {
                    bar(at: .now, duration: duration)
                }
            }
        }
    }

    private func bar(at date: Date, duration: TimeInterval) -> some View {
        let position = track.position(at: date)
        return VStack(spacing: 2) {
            MeterBar(value: track.progress(at: date) ?? 0, color: tint ?? theme.primary.opacity(0.85))
                .opacity(position == nil ? 0.4 : 1)
            HStack {
                Text(position.map(formatTime) ?? "–:––")
                Spacer()
                Text(formatTime(duration))
            }
            .font(theme.monospacedDigits(10))
            .foregroundStyle(theme.tertiary)
        }
    }
}
