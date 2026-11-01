import AppKit
import IslandCore
import IslandDesign
import Observation
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
public final class FileShelfModule: IslandModule, IslandDropTarget {
    public let id = FeatureID.shelf
    public let displayName = "File Shelf"
    public let symbolName = "tray.full"

    public private(set) var items: [ShelfItem] = []
    /// Items whose file is currently missing or unreadable.
    public private(set) var unavailable: Set<UUID> = []
    public private(set) var thumbnails: [UUID: NSImage] = [:]
    public private(set) var lastError: String?

    @ObservationIgnored private var expiry = ShelfExpiry.oneDay
    @ObservationIgnored private var maxItems = 30
    @ObservationIgnored private let store: JSONFileStore<[ShelfItem]>
    @ObservationIgnored private let activity: ActivityCenter
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var isActive = false

    public init(activity: ActivityCenter, fileURL: URL = AppPaths.file(named: "shelf.json")) {
        self.activity = activity
        self.store = JSONFileStore(fileURL: fileURL)
        do {
            items = try store.load() ?? []
        } catch {
            lastError = "The shelf could not be restored."
            store.quarantineFile()
        }
    }

    // MARK: IslandModule

    public func isEnabled(in settings: AppSettings) -> Bool {
        settings.shelf.isEnabled
    }

    public func apply(_ settings: AppSettings) {
        let changed = settings.shelf.expiry != expiry || settings.shelf.maxItems != maxItems
        expiry = settings.shelf.expiry
        maxItems = settings.shelf.maxItems
        if changed, isActive {
            prune()
        }
    }

    public func activate() {
        isActive = true
        // Files are not touched here: resolving them at launch could make macOS ask for access
        // to Desktop, Documents or Downloads before the user has opened the shelf.
        prune()
    }

    public func deactivate() {
        isActive = false
        expiryTask?.cancel()
        expiryTask = nil
        thumbnails.removeAll()
    }

    public func makeExpandedView() -> AnyView { AnyView(ShelfExpandedView(module: self)) }

    // MARK: Drop

    public func acceptDrop(of providers: [NSItemProvider]) -> Bool {
        let typeID = UTType.fileURL.identifier
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(typeID) }
        guard isActive, !fileProviders.isEmpty else { return false }

        // Providers load concurrently; gather everything so one drop yields one activity banner.
        let batch = DropBatch(expected: fileProviders.count) { [weak self] urls in self?.add(urls) }
        for provider in fileProviders {
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                Task { @MainActor in batch.receive(url) }
            }
        }
        return true
    }

    // MARK: Actions

    public func add(_ urls: [URL]) {
        let paths = ShelfPolicy.newPaths(urls.filter(\.isFileURL).map(ShelfPolicy.canonicalPath), existing: items)
        var added: [ShelfItem] = []
        var failures = 0

        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                added.append(ShelfItem(bookmark: bookmark, name: url.lastPathComponent, path: path, addedAt: .now))
            } catch {
                failures += 1
            }
        }

        lastError = failures > 0 ? "\(failures) item\(failures == 1 ? "" : "s") could not be added." : nil
        guard !added.isEmpty else { return }

        items.insert(contentsOf: added, at: 0)
        save()
        prune()
        for item in added {
            loadThumbnail(for: item)
        }

        let subtitle = added.count == 1 ? added[0].name : "\(added.count) files"
        activity.post(ActivityEvent(source: .shelf, title: "Added to Shelf", subtitle: subtitle, symbolName: "tray.and.arrow.down.fill"))
    }

    public func url(for item: ShelfItem) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: item.bookmark, options: [.withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &isStale
        ) else {
            unavailable.insert(item.id)
            return nil
        }
        if isStale || url.path != item.path {
            refreshBookmark(for: item, at: url)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            unavailable.insert(item.id)
            return nil
        }
        unavailable.remove(item.id)
        return url
    }

    public func open(_ item: ShelfItem) {
        guard let url = url(for: item) else { return }
        NSWorkspace.shared.open(url)
    }

    public func revealInFinder(_ item: ShelfItem) {
        guard let url = url(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Puts file references (not contents) on the clipboard, plus their paths as text.
    public func copyToPasteboard(_ selection: [ShelfItem]) {
        let urls = selection.compactMap(url(for:))
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    public func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        unavailable.remove(item.id)
        save()
        scheduleExpiry()
    }

    public func removeAll() {
        items.removeAll()
        thumbnails.removeAll()
        unavailable.removeAll()
        save()
        scheduleExpiry()
    }

    public func itemProvider(for item: ShelfItem) -> NSItemProvider {
        guard let url = url(for: item) else { return NSItemProvider() }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
    }

    public func icon(for item: ShelfItem) -> NSImage {
        thumbnails[item.id] ?? NSWorkspace.shared.icon(forFile: item.path)
    }

    /// Called when the shelf is shown: checks availability and loads thumbnails then, not at launch.
    public func ensureThumbnails() {
        refreshAvailability()
        for item in items where thumbnails[item.id] == nil {
            loadThumbnail(for: item)
        }
    }

    // MARK: Private

    private func refreshAvailability() {
        for item in items {
            _ = url(for: item)
        }
    }

    private func refreshBookmark(for item: ShelfItem, at url: URL) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        items[index].bookmark = bookmark
        items[index].path = url.path
        items[index].name = url.lastPathComponent
        save()
    }

    private func prune() {
        let kept = ShelfPolicy.pruned(items, now: .now, expiry: expiry, maxItems: maxItems)
        if kept != items {
            let keptIDs = Set(kept.map(\.id))
            thumbnails = thumbnails.filter { keptIDs.contains($0.key) }
            items = kept
            save()
        }
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard isActive, let next = ShelfPolicy.nextExpiry(items, expiry: expiry) else { return }
        let delay = max(next.timeIntervalSinceNow, 1)
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.prune()
        }
    }

    private func save() {
        do {
            try store.save(items)
        } catch {
            lastError = "The shelf could not be saved."
        }
    }

    private func loadThumbnail(for item: ShelfItem) {
        guard let url = url(for: item) else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: .thumbnail
        )
        let id = item.id
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.cgImage else { return }
            Task { @MainActor [weak self] in
                guard let self, self.items.contains(where: { $0.id == id }) else { return }
                self.thumbnails[id] = NSImage(cgImage: image, size: CGSize(width: 64, height: 64))
            }
        }
    }
}

@MainActor
private final class DropBatch {
    private var urls: [URL] = []
    private var remaining: Int
    private let completion: ([URL]) -> Void

    init(expected: Int, completion: @escaping ([URL]) -> Void) {
        self.remaining = expected
        self.completion = completion
    }

    func receive(_ url: URL?) {
        if let url { urls.append(url) }
        remaining -= 1
        if remaining == 0 { completion(urls) }
    }
}
