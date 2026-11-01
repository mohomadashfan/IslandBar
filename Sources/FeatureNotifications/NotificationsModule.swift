import AppKit
import IslandCore
import IslandDesign
import Observation
import SwiftUI
import UserNotifications

/// Shows IslandBar's own recent activity and, if the user opts in, mirrors it to macOS
/// Notification Center. It never reads notifications from other apps.
@MainActor
@Observable
public final class NotificationsModule: IslandModule {
    public let id = FeatureID.notifications
    public let displayName = "Activity"
    public let symbolName = "bell"

    public private(set) var systemAuthorization: UNAuthorizationStatus?
    public let activity: ActivityCenter

    @ObservationIgnored private var deliverToSystem = false
    @ObservationIgnored private var isActive = false

    public init(activity: ActivityCenter) {
        self.activity = activity
    }

    /// `UNUserNotificationCenter` requires a bundled app with an identifier.
    public static var isSystemDeliveryAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    // MARK: IslandModule

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.notifications.showHistoryTab || settings.notifications.deliverSystemNotifications
    }

    public func apply(_ settings: AppSettings) {
        let wanted = settings.notifications.deliverSystemNotifications && Self.isSystemDeliveryAvailable
        guard wanted != deliverToSystem else { return }
        deliverToSystem = wanted
        if wanted {
            requestAuthorization()
        }
    }

    public func activate() {
        isActive = true
        activity.onPost = { [weak self] event in self?.forward(event) }
        refreshAuthorization()
    }

    public func deactivate() {
        isActive = false
        activity.onPost = nil
    }

    public func makeExpandedView() -> AnyView { AnyView(ActivityHistoryView(module: self)) }

    // MARK: System notifications

    public func refreshAuthorization() {
        guard Self.isSystemDeliveryAvailable else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            self.systemAuthorization = settings.authorizationStatus
        }
    }

    public func requestAuthorization() {
        guard Self.isSystemDeliveryAvailable else { return }
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            self.refreshAuthorization()
        }
    }

    public static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func forward(_ event: ActivityEvent) {
        guard deliverToSystem, systemAuthorization == .authorized || systemAuthorization == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        if let subtitle = event.subtitle { content.body = subtitle }
        content.threadIdentifier = event.source.rawValue
        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}

struct ActivityHistoryView: View {
    let module: NotificationsModule
    @Environment(\.islandTheme) private var theme

    var body: some View {
        if module.activity.history.isEmpty {
            IslandEmptyState(symbol: "bell", title: "No recent activity", message: "Timer completions, shelf changes and build results appear here.")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Recent activity")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.secondary)
                    Spacer()
                    IslandPillButton("Clear") { module.activity.clearHistory() }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(module.activity.history) { event in
                            HStack(spacing: 8) {
                                Image(systemName: event.symbolName)
                                    .foregroundStyle(color(for: event.style))
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.title)
                                        .font(theme.font(12, weight: .medium))
                                        .foregroundStyle(theme.primary)
                                    if let subtitle = event.subtitle {
                                        Text(subtitle)
                                            .font(theme.font(10))
                                            .foregroundStyle(theme.secondary)
                                    }
                                }
                                .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(event.date, style: .time)
                                    .font(theme.font(10))
                                    .foregroundStyle(theme.tertiary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private func color(for style: ActivityStyle) -> Color {
        switch style {
        case .info: theme.accent
        case .success: .green
        case .warning: .orange
        case .failure: .red
        }
    }
}
