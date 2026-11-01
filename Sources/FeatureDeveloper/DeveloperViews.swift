import IslandDesign
import SwiftUI

private extension DeveloperActivity {
    func tint(_ theme: IslandTheme) -> Color {
        switch event.state {
        case .succeeded: .green
        case .failed: .red
        case .cancelled: theme.tertiary
        default: theme.accent
        }
    }
}

struct DeveloperCompactLeading: View {
    let module: DeveloperModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        if let activity = module.currentActivity {
            Image(systemName: activity.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activity.tint(theme))
                .symbolEffect(.pulse, options: .repeating, isActive: true)
        }
    }
}

struct DeveloperCompactTrailing: View {
    let module: DeveloperModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        if let activity = module.currentActivity {
            Group {
                if let progress = activity.event.progress {
                    HStack(spacing: 4) {
                        Text("\(Int(progress * 100))%")
                            .font(theme.monospacedDigits(11, weight: .semibold))
                        ProgressRing(progress: progress, lineWidth: 2.5, color: activity.tint(theme))
                            .frame(width: 13, height: 13)
                    }
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .foregroundStyle(theme.primary)
        }
    }
}

struct DeveloperExpandedView: View {
    let module: DeveloperModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        if module.repositories.isEmpty && module.log.activities.isEmpty {
            IslandEmptyState(
                symbol: "hammer",
                title: "No developer activity",
                message: "Add repositories in Settings › Developer, or send events from your tools."
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if !module.log.activities.isEmpty {
                        sectionHeader("Activity") {
                            if module.log.activities.contains(where: { !$0.isActive }) {
                                IslandPillButton("Clear") { module.clearFinished() }
                            }
                        }
                        ForEach(module.log.activities) { ActivityRow(activity: $0) }
                    }
                    if !module.repositories.isEmpty {
                        sectionHeader("Repositories") {
                            IslandPillButton("Refresh", symbol: "arrow.clockwise") { module.refreshAllRepositories() }
                        }
                        ForEach(module.repositories) { repository in
                            RepositoryRow(status: repository)
                                .onTapGesture(count: 2) { module.revealRepository(repository) }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(theme.captionFont)
                .foregroundStyle(theme.secondary)
            Spacer()
            trailing()
        }
        .padding(.top, 2)
    }
}

private struct ActivityRow: View {
    let activity: DeveloperActivity
    @Environment(\.islandTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: activity.symbolName)
                .foregroundStyle(activity.tint(theme))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.event.title)
                    .font(theme.font(12, weight: .medium))
                    .foregroundStyle(theme.primary)
                    .lineLimit(1)
                Text([activity.event.source, activity.event.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(theme.font(10))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if activity.isActive {
                if let progress = activity.event.progress {
                    ProgressRing(progress: progress, lineWidth: 2.5).frame(width: 14, height: 14)
                } else {
                    ProgressView().controlSize(.mini)
                }
            } else {
                Text(activity.updatedAt, style: .relative)
                    .font(theme.font(10))
                    .foregroundStyle(theme.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct RepositoryRow: View {
    let status: RepositoryStatus
    @Environment(\.islandTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(theme.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(status.name)
                        .font(theme.font(12, weight: .medium))
                        .foregroundStyle(theme.primary)
                    if let branch = status.summary?.branch {
                        Text(branch)
                            .font(theme.font(10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(theme.fill))
                            .foregroundStyle(theme.secondary)
                    }
                }
                .lineLimit(1)
                Text(subtitle)
                    .font(theme.font(10))
                    .foregroundStyle(status.error == nil ? theme.secondary : .orange)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let summary = status.summary {
                HStack(spacing: 6) {
                    if summary.ahead > 0 { Label("\(summary.ahead)", systemImage: "arrow.up") }
                    if summary.behind > 0 { Label("\(summary.behind)", systemImage: "arrow.down") }
                    if summary.isClean {
                        Image(systemName: "checkmark").foregroundStyle(.green)
                    } else {
                        Label("\(summary.changedFiles)", systemImage: "pencil")
                    }
                }
                .labelStyle(CompactLabelStyle())
                .font(theme.monospacedDigits(10))
                .foregroundStyle(theme.secondary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help(status.path)
    }

    private var subtitle: String {
        if let error = status.error { return error }
        guard let summary = status.summary else { return "Checking…" }
        var parts: [String] = []
        if summary.staged > 0 { parts.append("\(summary.staged) staged") }
        if summary.unstaged > 0 { parts.append("\(summary.unstaged) modified") }
        if summary.untracked > 0 { parts.append("\(summary.untracked) untracked") }
        if summary.conflicted > 0 { parts.append("\(summary.conflicted) conflicted") }
        if parts.isEmpty, let commit = status.lastCommit {
            parts.append(commit + (status.lastCommitAge.map { " · \($0)" } ?? ""))
        }
        return parts.isEmpty ? "Clean" : parts.joined(separator: ", ")
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.font(.system(size: 8, weight: .bold))
            configuration.title
        }
    }
}
