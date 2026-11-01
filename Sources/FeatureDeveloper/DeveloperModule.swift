import AppKit
import IslandCore
import IslandDesign
import Observation
import SwiftUI

@MainActor
@Observable
public final class DeveloperModule: IslandModule {
    public let id = FeatureID.developer
    public let displayName = "Developer"
    public let symbolName = "hammer"

    public private(set) var repositories: [RepositoryStatus] = []
    public private(set) var log = DeveloperActivityLog()
    public private(set) var inboxError: String?
    public private(set) var rejectedEventCount = 0

    @ObservationIgnored private var settings = DeveloperSettings()
    @ObservationIgnored private let activity: ActivityCenter
    @ObservationIgnored private let inboxURL: URL
    @ObservationIgnored private var inboxWatcher: DirectoryWatcher?
    @ObservationIgnored private var repoWatcher: FileEventStream?
    @ObservationIgnored private var refreshTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastRefresh: [String: Date] = [:]
    @ObservationIgnored private var staleTask: Task<Void, Never>?
    @ObservationIgnored private var isActive = false

    /// Hooks are untrusted: bound how much we read per file and per batch.
    static let maxEventFileSize = 16 * 1024
    static let maxEventsPerBatch = 100
    /// Minimum spacing between `git status` runs for one repository.
    static let repositoryRefreshInterval: TimeInterval = 3

    public init(activity: ActivityCenter, inboxURL: URL = AppPaths.eventInboxDirectory()) {
        self.activity = activity
        self.inboxURL = inboxURL
    }

    // MARK: IslandModule

    public var liveActivityPriority: Int? {
        guard settings.showLiveActivity, currentActivity != nil else { return nil }
        return LiveActivityPriority.developer
    }

    /// The most recently updated running activity.
    public var currentActivity: DeveloperActivity? {
        log.activities.first(where: \.isActive)
    }

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.developer.isEnabled
    }

    public func apply(_ settings: AppSettings) {
        let previous = self.settings
        self.settings = settings.developer
        guard isActive else { return }
        if previous.repositories != settings.developer.repositories {
            startRepositoryWatching()
        }
        if previous.eventInboxEnabled != settings.developer.eventInboxEnabled {
            settings.developer.eventInboxEnabled ? startInbox() : stopInbox()
        }
        scheduleStaleCheck()
    }

    public func activate() {
        isActive = true
        startRepositoryWatching()
        if settings.eventInboxEnabled {
            startInbox()
        }
    }

    public func deactivate() {
        isActive = false
        stopInbox()
        repoWatcher?.stop()
        repoWatcher = nil
        for task in refreshTasks.values { task.cancel() }
        refreshTasks.removeAll()
        staleTask?.cancel()
        staleTask = nil
    }

    public func makeCompactLeading() -> AnyView { AnyView(DeveloperCompactLeading(module: self)) }
    public func makeCompactTrailing() -> AnyView { AnyView(DeveloperCompactTrailing(module: self)) }
    public func makeExpandedView() -> AnyView { AnyView(DeveloperExpandedView(module: self)) }

    // MARK: Actions

    public func refreshAllRepositories() {
        for path in settings.repositories {
            refresh(path, force: true)
        }
    }

    public func clearFinished() {
        log.clearFinished()
    }

    public func revealRepository(_ status: RepositoryStatus) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: status.path)])
    }

    public var inboxPath: String { inboxURL.path }

    // MARK: Repositories

    private func startRepositoryWatching() {
        repoWatcher?.stop()
        repoWatcher = nil
        let paths = settings.repositories
        repositories = paths.map { path in
            repositories.first(where: { $0.path == path }) ?? RepositoryStatus(path: path)
        }
        for (path, task) in refreshTasks where !paths.contains(path) {
            task.cancel()
            refreshTasks[path] = nil
        }
        guard !paths.isEmpty else { return }

        let watcher = FileEventStream(paths: paths, latency: 1.0) { [weak self] changed in
            self?.filesChanged(changed)
        }
        watcher.start()
        repoWatcher = watcher
        refreshAllRepositories()
    }

    private func filesChanged(_ changedPaths: [String]) {
        for repository in settings.repositories {
            let prefix = repository.hasSuffix("/") ? repository : repository + "/"
            let relevant = changedPaths.contains { path in
                (path == repository || path.hasPrefix(prefix)) && !Self.isNoise(path)
            }
            if relevant {
                refresh(repository, force: false)
            }
        }
    }

    /// Object-store churn does not change status; skip it to avoid needless git runs.
    nonisolated static func isNoise(_ path: String) -> Bool {
        path.contains("/.git/objects/") || path.contains("/.git/logs/") || path.hasSuffix(".lock")
    }

    private func refresh(_ path: String, force: Bool) {
        guard isActive, refreshTasks[path] == nil else { return }
        let elapsed = lastRefresh[path].map { Date.now.timeIntervalSince($0) } ?? .infinity
        let wait = force ? 0 : max(0, Self.repositoryRefreshInterval - elapsed)

        refreshTasks[path] = Task { [weak self] in
            if wait > 0 {
                try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
            }
            guard !Task.isCancelled else { return }
            let status = await GitClient.status(of: path)
            guard let self, !Task.isCancelled else { return }
            self.refreshTasks[path] = nil
            self.lastRefresh[path] = .now
            if let index = self.repositories.firstIndex(where: { $0.path == path }) {
                self.repositories[index] = status
            }
        }
    }

    // MARK: Event inbox

    private func startInbox() {
        guard inboxWatcher == nil else { return }
        do {
            try FileManager.default.createDirectory(
                at: inboxURL, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            inboxError = "Could not create the events folder."
            return
        }
        let watcher = DirectoryWatcher(url: inboxURL) { [weak self] in self?.drainInbox() }
        guard watcher.start() else {
            inboxError = "Could not watch the events folder."
            return
        }
        inboxWatcher = watcher
        inboxError = nil
        drainInbox()
    }

    private func stopInbox() {
        inboxWatcher?.stop()
        inboxWatcher = nil
    }

    /// Reads and deletes event files. Files are processed in creation order; anything invalid is
    /// discarded and counted.
    private func drainInbox() {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: inboxURL, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let files = entries
            .filter { $0.pathExtension == "json" }
            .sorted { creationDate($0) < creationDate($1) }
            .prefix(Self.maxEventsPerBatch)

        for file in files {
            defer { try? manager.removeItem(at: file) }
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? .max) <= Self.maxEventFileSize,
                  let data = try? Data(contentsOf: file),
                  let event = try? DeveloperEvent.decode(data)
            else {
                rejectedEventCount += 1
                continue
            }
            receive(event)
        }
        if entries.count > files.count {
            // More remain; continue on the next turn of the run loop.
            Task { [weak self] in self?.drainInbox() }
        }
    }

    private func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    func receive(_ event: DeveloperEvent) {
        if let finished = log.apply(event, receivedAt: .now) {
            announce(finished)
        }
        scheduleStaleCheck()
    }

    private func announce(_ activity: DeveloperActivity) {
        let event = activity.event
        let style: ActivityStyle = switch event.state {
        case .succeeded: .success
        case .failed: .failure
        default: .info
        }
        let verb = switch event.state {
        case .succeeded: "succeeded"
        case .failed: "failed"
        default: "cancelled"
        }
        self.activity.post(ActivityEvent(
            source: .developer, style: style,
            title: "\(event.title) \(verb)",
            subtitle: event.detail ?? event.source,
            symbolName: activity.symbolName
        ))
    }

    private func scheduleStaleCheck() {
        staleTask?.cancel()
        staleTask = nil
        guard isActive, log.activities.contains(where: \.isActive) else { return }
        let staleAfter = max(settings.staleActivityMinutes, 1) * 60
        staleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            _ = self.log.expireStale(now: .now, staleAfter: staleAfter)
            self.scheduleStaleCheck()
        }
    }
}
