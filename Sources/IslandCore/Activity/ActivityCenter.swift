import Foundation
import Observation

public enum ActivitySource: String, Codable, Sendable, CaseIterable {
    case app, focus, shelf, developer, media, system, privacy, devices
}

public enum ActivityStyle: String, Codable, Sendable {
    case info, success, warning, failure
}

/// Something worth briefly showing in the island, posted by a feature module.
public struct ActivityEvent: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var source: ActivitySource
    public var style: ActivityStyle
    public var title: String
    public var subtitle: String?
    public var symbolName: String
    public var date: Date

    public init(
        source: ActivitySource,
        style: ActivityStyle = .info,
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        date: Date = .now,
        id: UUID = UUID()
    ) {
        self.id = id
        self.source = source
        self.style = style
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.date = date
    }
}

/// Queues application-owned activity and shows one banner at a time.
///
/// This only carries events IslandBar itself produces; it has no access to other apps'
/// notifications.
@MainActor
@Observable
public final class ActivityCenter {
    public struct Configuration: Sendable, Equatable {
        public var bannersEnabled = true
        public var bannerDuration: Duration = .seconds(4)
        public var enabledSources = Set(ActivitySource.allCases)
        public var historyLimit = 30

        public init() {}

        public init(_ settings: NotificationSettings) {
            bannersEnabled = settings.showBanners
            bannerDuration = .milliseconds(Int(max(settings.bannerDuration, 1) * 1000))
            enabledSources = settings.enabledSources
            historyLimit = max(settings.historyLimit, 0)
        }
    }

    public var configuration = Configuration() {
        didSet { trimHistory() }
    }

    /// The banner currently on screen.
    public private(set) var current: ActivityEvent?
    /// Most recent first.
    public private(set) var history: [ActivityEvent] = []

    /// Called for every event from an enabled source, e.g. to forward to macOS notifications.
    @ObservationIgnored public var onPost: ((ActivityEvent) -> Void)?

    @ObservationIgnored private var queue: [ActivityEvent] = []
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void

    public init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    public var pendingCount: Int { queue.count }

    public func post(_ event: ActivityEvent) {
        history.insert(event, at: 0)
        trimHistory()

        guard configuration.enabledSources.contains(event.source) else { return }
        onPost?(event)

        guard configuration.bannersEnabled else { return }
        if current == nil {
            show(event)
        } else {
            queue.append(event)
        }
    }

    public func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        if !queue.isEmpty {
            show(queue.removeFirst())
        }
    }

    public func clearHistory() {
        history.removeAll()
    }

    private func show(_ event: ActivityEvent) {
        current = event
        let duration = configuration.bannerDuration
        dismissTask = Task { [weak self, sleep] in
            do {
                try await sleep(duration)
            } catch {
                return
            }
            guard let self, self.current?.id == event.id else { return }
            self.dismissCurrent()
        }
    }

    private func trimHistory() {
        if history.count > configuration.historyLimit {
            history.removeLast(history.count - configuration.historyLimit)
        }
    }
}
