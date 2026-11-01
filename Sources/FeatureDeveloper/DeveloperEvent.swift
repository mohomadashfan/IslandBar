import Foundation

/// One event written by a local hook (build script, VS Code task, coding agent, ...).
///
/// Schema (JSON), see docs/INTEGRATIONS.md:
/// `{"source": "vscode", "kind": "build", "state": "running", "title": "swift build",
///   "detail": "Compiling 12 files", "progress": 0.4, "session": "abc", "timestamp": "2026-01-01T10:00:00Z"}`
public struct DeveloperEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case build, test, agent, task, deploy, custom
    }

    public enum State: String, Codable, Sendable, CaseIterable {
        case started, running, waiting, succeeded, failed, cancelled, info

        public var isActive: Bool {
            self == .started || self == .running || self == .waiting
        }

        public var isFinished: Bool {
            self == .succeeded || self == .failed || self == .cancelled
        }
    }

    public static let maxTextLength = 200

    public var source: String
    public var kind: Kind
    public var state: State
    public var title: String
    public var detail: String?
    public var progress: Double?
    public var session: String?
    public var timestamp: Date?

    public init(
        source: String, kind: Kind, state: State, title: String, detail: String? = nil,
        progress: Double? = nil, session: String? = nil, timestamp: Date? = nil
    ) {
        self.source = source
        self.kind = kind
        self.state = state
        self.title = title
        self.detail = detail
        self.progress = progress
        self.session = session
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case source, kind, state, title, detail, progress, session, timestamp
    }

    /// Lenient about unknown kinds/states (future hook versions) but strict about required text.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = Self.clean(try container.decode(String.self, forKey: .source))
        title = Self.clean(try container.decode(String.self, forKey: .title))
        guard !source.isEmpty, !title.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: container, debugDescription: "source and title must not be empty")
        }
        let kindName = try container.decodeIfPresent(String.self, forKey: .kind) ?? "custom"
        kind = Kind(rawValue: kindName.lowercased()) ?? .custom
        let stateName = try container.decodeIfPresent(String.self, forKey: .state) ?? "info"
        state = State(rawValue: stateName.lowercased()) ?? .info
        detail = try container.decodeIfPresent(String.self, forKey: .detail).map(Self.clean)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress).map { min(max($0, 0), 1) }
        session = try container.decodeIfPresent(String.self, forKey: .session).map(Self.clean)
        timestamp = try? container.decodeIfPresent(Date.self, forKey: .timestamp)
    }

    /// Single line, trimmed, length-limited: hooks are untrusted input.
    static func clean(_ text: String) -> String {
        let singleLine = text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLine.prefix(maxTextLength))
    }

    public static func decode(_ data: Data) throws -> DeveloperEvent {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DeveloperEvent.self, from: data)
    }

    /// Events from the same source and session (or kind, when no session) update one activity.
    public var activityKey: String {
        "\(source)|\(session ?? kind.rawValue)"
    }
}

/// The latest state of one running or recently finished thing.
public struct DeveloperActivity: Identifiable, Sendable, Equatable {
    public var id: String
    public var event: DeveloperEvent
    public var startedAt: Date
    public var updatedAt: Date

    public var isActive: Bool { event.state.isActive }

    public var symbolName: String {
        switch event.state {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle.fill"
        case .waiting: "hourglass"
        case .info: "info.circle"
        case .started, .running:
            switch event.kind {
            case .build: "hammer.fill"
            case .test: "checklist"
            case .agent: "sparkles"
            case .task: "list.bullet.rectangle"
            case .deploy: "paperplane.fill"
            case .custom: "bolt.fill"
            }
        }
    }
}

/// Pure bookkeeping for activities, separated for testing.
public struct DeveloperActivityLog: Sendable, Equatable {
    public private(set) var activities: [DeveloperActivity] = []
    public var limit = 20

    public init() {}

    /// Applies an event. Returns the updated activity when it just transitioned to finished.
    @discardableResult
    public mutating func apply(_ event: DeveloperEvent, receivedAt: Date) -> DeveloperActivity? {
        let date = event.timestamp ?? receivedAt
        let key = event.activityKey
        var finished: DeveloperActivity?

        if let index = activities.firstIndex(where: { $0.id == key }) {
            let wasFinished = activities[index].event.state.isFinished
            activities[index].event = event
            activities[index].updatedAt = date
            if event.state.isActive, wasFinished {
                activities[index].startedAt = date
            }
            if event.state.isFinished, !wasFinished {
                finished = activities[index]
            }
        } else {
            let activity = DeveloperActivity(id: key, event: event, startedAt: date, updatedAt: date)
            activities.append(activity)
            if event.state.isFinished {
                finished = activity
            }
        }

        activities.sort { $0.updatedAt > $1.updatedAt }
        if activities.count > limit {
            activities.removeLast(activities.count - limit)
        }
        return finished
    }

    /// Active entries with no update for `staleAfter` are marked cancelled.
    public mutating func expireStale(now: Date, staleAfter: TimeInterval) -> Bool {
        var changed = false
        for index in activities.indices where activities[index].isActive {
            if now.timeIntervalSince(activities[index].updatedAt) >= staleAfter {
                activities[index].event.state = .cancelled
                activities[index].event.detail = "No updates received"
                changed = true
            }
        }
        return changed
    }

    public mutating func clearFinished() {
        activities.removeAll { !$0.isActive }
    }
}
