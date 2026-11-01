import IslandDesign
import SwiftUI

private func formatClock(_ interval: TimeInterval) -> String {
    let total = Int(interval.rounded(.up))
    return String(format: "%d:%02d", total / 60, total % 60)
}

private extension FocusModule {
    func phaseColor(_ theme: IslandTheme) -> Color {
        timer.phase == .work ? theme.accent : .teal
    }
}

/// Re-renders once a second only while the timer is running.
private struct FocusTicker<Content: View>: View {
    let isRunning: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in content(context.date) }
        } else {
            content(.now)
        }
    }
}

struct FocusCompactLeading: View {
    let module: FocusModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        FocusTicker(isRunning: module.timer.isRunning) { now in
            ProgressRing(
                progress: module.timer.progress(at: now, durations: module.durations),
                lineWidth: 2.5,
                color: module.phaseColor(theme)
            )
            .frame(width: 15, height: 15)
        }
        .accessibilityLabel(module.timer.phase.displayName)
    }
}

struct FocusCompactTrailing: View {
    let module: FocusModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        FocusTicker(isRunning: module.timer.isRunning) { now in
            HStack(spacing: 3) {
                if module.timer.isPaused {
                    Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold))
                }
                Text(formatClock(module.timer.remaining(at: now, durations: module.durations)))
                    .font(theme.monospacedDigits(12, weight: .semibold))
            }
            .foregroundStyle(module.phaseColor(theme))
        }
    }
}

struct FocusExpandedView: View {
    @Bindable var module: FocusModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: theme.padding) {
            timerColumn
            Rectangle().fill(theme.fill).frame(width: 1)
            notesColumn
        }
    }

    private var timerColumn: some View {
        HStack(spacing: theme.padding) {
            FocusTicker(isRunning: module.timer.isRunning) { now in
                ZStack {
                    ProgressRing(
                        progress: module.timer.progress(at: now, durations: module.durations),
                        lineWidth: 5,
                        color: module.phaseColor(theme)
                    )
                    Text(formatClock(module.timer.remaining(at: now, durations: module.durations)))
                        .font(theme.monospacedDigits(17, weight: .semibold))
                        .foregroundStyle(theme.primary)
                }
                .frame(width: 84, height: 84)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(module.timer.phase.displayName, systemImage: module.timer.phase.symbolName)
                    .font(theme.headlineFont)
                    .foregroundStyle(theme.primary)
                    .fixedSize()

                sessionDots

                HStack(spacing: 4) {
                    IslandIconButton(
                        module.timer.isRunning ? "pause.fill" : "play.fill",
                        prominent: true,
                        help: module.timer.isRunning ? "Pause" : (module.timer.isPaused ? "Resume" : "Start")
                    ) { module.startOrPause() }
                    IslandIconButton("arrow.counterclockwise", size: 12, help: "Restart this phase") { module.resetPhase() }
                    IslandIconButton("forward.end.fill", size: 12, help: "Skip to next phase") { module.skip() }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .contextMenu {
            Button("Reset All Sessions") { module.resetAll() }
        }
    }

    private var sessionDots: some View {
        let total = module.durations.sessionsBeforeLongBreak
        let done = module.timer.sessionInCycle(durations: module.durations)
        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < done ? module.phaseColor(theme) : theme.tertiary)
                    .frame(width: 6, height: 6)
            }
            Text("\(module.timer.completedWorkSessions) done")
                .font(theme.captionFont)
                .foregroundStyle(theme.secondary)
                .padding(.leading, 4)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(module.timer.completedWorkSessions) sessions completed")
    }

    private var notesColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quick notes")
                .font(theme.captionFont)
                .foregroundStyle(theme.secondary)
            TextEditor(text: $module.notes)
                .font(theme.font(12))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .foregroundStyle(theme.primary)
                .padding(6)
                .islandCard(cornerRadius: 8)
        }
        .frame(maxWidth: .infinity)
    }
}
