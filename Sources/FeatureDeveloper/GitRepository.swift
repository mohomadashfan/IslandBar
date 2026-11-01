import Foundation

public struct GitStatusSummary: Sendable, Equatable {
    public var branch: String?
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var staged = 0
    public var unstaged = 0
    public var untracked = 0
    public var conflicted = 0

    public init() {}

    public var changedFiles: Int { staged + unstaged + untracked + conflicted }
    public var isClean: Bool { changedFiles == 0 }
}

public struct RepositoryStatus: Identifiable, Sendable, Equatable {
    public var path: String
    public var summary: GitStatusSummary?
    public var lastCommit: String?
    public var lastCommitAge: String?
    public var error: String?
    public var updatedAt: Date?

    public init(path: String) {
        self.path = path
    }

    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// Pure parsers for git's machine-readable output.
public enum GitParser {
    /// Parses `git status --porcelain=v1 --branch`.
    public static func parseStatus(_ output: String) -> GitStatusSummary {
        var summary = GitStatusSummary()
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("## ") {
                parseBranchLine(line.dropFirst(3), into: &summary)
                continue
            }
            guard line.count >= 2 else { continue }
            let x = line[line.startIndex]
            let y = line[line.index(after: line.startIndex)]

            if x == "?" && y == "?" {
                summary.untracked += 1
            } else if x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D") {
                summary.conflicted += 1
            } else {
                if x != " " && x != "!" { summary.staged += 1 }
                if y != " " && y != "!" { summary.unstaged += 1 }
            }
        }
        return summary
    }

    private static func parseBranchLine(_ line: Substring, into summary: inout GitStatusSummary) {
        // Forms: "main", "main...origin/main", "main...origin/main [ahead 1, behind 2]",
        // "No commits yet on main", "HEAD (no branch)"
        var text = String(line)
        if let bracket = text.range(of: " [") {
            let tracking = text[bracket.upperBound...].dropLast(text.hasSuffix("]") ? 1 : 0)
            for part in tracking.split(separator: ",") {
                let words = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard words.count == 2, let count = Int(words[1]) else { continue }
                if words[0] == "ahead" { summary.ahead = count }
                if words[0] == "behind" { summary.behind = count }
            }
            text = String(text[..<bracket.lowerBound])
        }
        if text.hasPrefix("No commits yet on ") {
            summary.branch = String(text.dropFirst("No commits yet on ".count))
        } else if text.hasPrefix("HEAD (no branch)") {
            summary.branch = nil
        } else if let dots = text.range(of: "...") {
            summary.branch = String(text[..<dots.lowerBound])
            summary.upstream = String(text[dots.upperBound...])
        } else {
            summary.branch = text
        }
    }

    /// Parses `git log -1 --format=%s%x1f%cr`.
    public static func parseLastCommit(_ output: String) -> (subject: String, age: String)? {
        let parts = output.trimmingCharacters(in: .newlines).split(separator: "\u{1F}", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    /// True if `path` contains a `.git` directory or file (worktrees use a file).
    public static func isRepository(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
    }
}

enum GitError: Error, Equatable {
    case gitUnavailable
    case failed(status: Int32, message: String)
    case timedOut
}

/// Runs the system git with read-only commands. `GIT_OPTIONAL_LOCKS=0` stops `git status` from
/// refreshing the index, so IslandBar never contends with the user's own git operations.
enum GitClient {
    static let executable = "/usr/bin/git"

    static func status(of repository: String) async -> RepositoryStatus {
        var status = RepositoryStatus(path: repository)
        status.updatedAt = .now
        guard GitParser.isRepository(repository) else {
            status.error = "Not a Git repository"
            return status
        }
        do {
            let output = try await run(["status", "--porcelain=v1", "--branch"], in: repository)
            status.summary = GitParser.parseStatus(output)
            if let log = try? await run(["log", "-1", "--format=%s%x1f%cr"], in: repository),
               let commit = GitParser.parseLastCommit(log) {
                status.lastCommit = commit.subject
                status.lastCommitAge = commit.age
            }
        } catch GitError.gitUnavailable {
            status.error = "Git is not installed (install the Xcode Command Line Tools)"
        } catch GitError.timedOut {
            status.error = "git status timed out"
        } catch GitError.failed(_, let message) {
            status.error = message.isEmpty ? "git status failed" : message
        } catch {
            status.error = error.localizedDescription
        }
        return status
    }

    static func run(_ arguments: [String], in directory: String, timeout: Duration = .seconds(15)) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw GitError.gitUnavailable }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-C", directory, "--no-pager"] + arguments
        process.environment = [
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_TERMINAL_PROMPT": "0",
            "LC_ALL": "C",
            "PATH": "/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .utility).async {
                        do {
                            try process.run()
                        } catch {
                            continuation.resume(throwing: GitError.gitUnavailable)
                            return
                        }
                        // Read before waiting so large output cannot fill the pipe and deadlock.
                        let data = stdout.fileHandleForReading.readDataToEndOfFile()
                        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()
                        if process.terminationStatus == 0 {
                            continuation.resume(returning: String(decoding: data, as: UTF8.self))
                        } else {
                            let message = String(decoding: errorData, as: UTF8.self)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            continuation.resume(throwing: GitError.failed(status: process.terminationStatus, message: String(message.prefix(160))))
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                if process.isRunning { process.terminate() }
                throw GitError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw GitError.timedOut }
            return result
        }
    }
}
