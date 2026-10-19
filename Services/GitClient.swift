import Foundation
import Darwin

struct GitClient: Sendable {
    enum GitClientError: LocalizedError {
        case commandFailed(String)
        case invalidOutput
        case commandTimedOut

        var errorDescription: String? {
            switch self {
            case .commandFailed(let message):
                return message
            case .invalidOutput:
                return "Git returned output in an unexpected format."
            case .commandTimedOut:
                return "Origin did not respond in time. Showing previously fetched remote branches."
            }
        }
    }

    /// Refresh only origin's remote-tracking branches; never merge into local branches.
    /// Returns false for repositories without an origin remote.
    func fetchOrigin(repository: GitRepository, timeout: TimeInterval = 30) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            let remotes = try runGit(["remote"], in: repository.path)
            guard remotes.split(separator: "\n").contains("origin") else { return false }

            var environment = [
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_ASKPASS": "/usr/bin/false",
                "SSH_ASKPASS": "/usr/bin/false",
                "GCM_INTERACTIVE": "Never"
            ]
            let ssh = ProcessInfo.processInfo.environment["GIT_SSH_COMMAND"] ?? "ssh"
            environment["GIT_SSH_COMMAND"] = ssh + " -oBatchMode=yes -oConnectTimeout=10 -oServerAliveInterval=10 -oServerAliveCountMax=1"
            _ = try runGit([
                "fetch", "--prune", "--no-prune-tags", "--no-tags", "--no-recurse-submodules", "origin",
                "+refs/heads/*:refs/remotes/origin/*"
            ], in: repository.path, environmentOverrides: environment, timeout: timeout)
            return true
        }.value
    }

    func loadHistory(repository: GitRepository) async throws -> [CommitRow] {
        try await Task.detached(priority: .userInitiated) {
            try loadHistorySync(repository: repository)
        }.value
    }

    func currentBranch(repository: GitRepository) async -> String? {
        await Task.detached(priority: .utility) {
            if let branch = try? runGit(["symbolic-ref", "--quiet", "--short", "HEAD"], in: repository.path)
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !branch.isEmpty {
                return branch
            }

            return try? runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repository.path)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    func localChangesCount(repository: GitRepository) async throws -> Int {
        try await Task.detached(priority: .utility) {
            try Set(workingTreeEntries(in: repository.path).map(\.path)).count
        }.value
    }

    func loadWorkingTreeChanges(repository: GitRepository) async throws -> CommitChanges {
        try await Task.detached(priority: .userInitiated) {
            let entries = try workingTreeEntries(in: repository.path)
            let head = try? runGit(["rev-parse", "--verify", "HEAD"], in: repository.path)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let base = try head ?? runGit(["hash-object", "-t", "tree", "/dev/null"], in: repository.path)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let common = ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "--ignore-submodules=none", "-M"]
            let status = try runGit(common + ["--name-status", "-z", base, "--"], in: repository.path)
            let stats = try runGit(common + ["--numstat", "-z", base, "--"], in: repository.path)
            let changedPaths = Set(entries.map(\.path))
            var files = try GitDiffParser.files(statusOutput: status, statOutput: stats, allowsUnchangedFiles: true)
                .filter { changedPaths.contains($0.path) || $0.previousPath.map(changedPaths.contains) == true }
                .reduce(into: [String: CommitChangedFile]()) { $0[$1.path] = $1 }
            for entry in entries {
                if entry.isUntracked {
                    let output = try workingTreeFileDiff(path: entry.path, base: base, repository: repository, numstat: true)
                    let counts = output.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                    let existsInHead = (try? runGit(["cat-file", "-e", base + ":" + entry.path], in: repository.path)) != nil
                    let additions = counts.first.flatMap { Int($0) }
                    let deletions = counts.count > 1 ? Int(counts[1]) : nil
                    files[entry.path] = CommitChangedFile(path: entry.path, previousPath: nil,
                        status: existsInHead ? (additions == 0 && deletions == 0 ? "S" : "M") : "A",
                        additions: additions, deletions: deletions)
                } else if entry.isUnmerged, let file = files[entry.path] {
                    files[entry.path] = CommitChangedFile(path: file.path, previousPath: file.previousPath,
                        status: "U", additions: file.additions, deletions: file.deletions)
                } else if let file = files[entry.path], file.status == "M", file.additions == 0, file.deletions == 0,
                          entry.status.first != " " {
                    files[entry.path] = CommitChangedFile(path: file.path, previousPath: nil,
                        status: "S", additions: 0, deletions: 0)
                } else if files[entry.path] == nil {
                    // Staged edits can be undone in the working copy while still uncommitted.
                    files[entry.path] = CommitChangedFile(path: entry.path, previousPath: entry.previousPath,
                        status: entry.isUnmerged ? "U" : "S", additions: 0, deletions: 0)
                }
            }
            return CommitChanges(baseRevision: base, files: files.values.sorted { $0.path < $1.path },
                message: "", baseLabel: head == nil ? "Empty tree" : "HEAD")
        }.value
    }

    func loadWorkingTreeDiff(repository: GitRepository, base: String, file: CommitChangedFile) async throws -> FileDiff {
        try await Task.detached(priority: .userInitiated) {
            let entries = try workingTreeEntries(in: repository.path)
            if entries.contains(where: { $0.path == file.path && $0.isUntracked }) {
                return GitDiffParser.diff(try workingTreeFileDiff(path: file.path, base: base, repository: repository))
            }
            var paths = [file.path]
            if let previous = file.previousPath, previous != file.path { paths.insert(previous, at: 0) }
            let output = try runGit([
                "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--ignore-submodules=none", "--submodule=short",
                "--patch", "--raw", "-z", "-M", "--unified=3", base, "--"
            ] + paths.map { ":(literal)" + $0 }, in: repository.path)
            let diff = GitDiffParser.diff(try GitDiffParser.patch(for: file.path, in: output))
            if diff.lines.isEmpty, file.status == "S" {
                return FileDiff(lines: [DiffLine(id: 0, kind: .notice,
                    text: "The working copy matches HEAD. This file still has staged changes.",
                    oldNumber: nil, newNumber: nil)], isBinary: false)
            }
            return diff
        }.value
    }

    private func workingTreeEntries(in directory: URL) throws -> [WorkingTreeEntry] {
        try GitDiffParser.workingTreeEntries(runGit([
            "--no-optional-locks", "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none"
        ], in: directory))
    }

    /// Untracked files are absent from `git diff HEAD`. Compare them without touching the index.
    /// Reading the HEAD blob also handles a staged deletion recreated at the same path.
    private func workingTreeFileDiff(path: String, base: String, repository: GitRepository, numstat: Bool = false) throws -> String {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("DonGit-base-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var oldPath = "/dev/null"
        if let contents = try? runGitData(["cat-file", "blob", base + ":" + path], in: repository.path) {
            try contents.write(to: temporary)
            oldPath = temporary.path
        }
        return try runGit([
            "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--no-index",
            numstat ? "--numstat" : "--patch", "--unified=3", "--", oldPath,
            repository.path.appendingPathComponent(path).path
        ], in: repository.path, allowedExitCodes: [0, 1])
    }

    func commitAllChanges(repository: GitRepository, message: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            _ = try runGit(["add", "-A"], in: repository.path)
            _ = try runGit(["commit", "-m", message], in: repository.path)
        }.value
    }

    func historySignature(repository: GitRepository) async throws -> String {
        try await Task.detached(priority: .utility) {
            let head = (try? runGit(["rev-parse", "--verify", "HEAD"], in: repository.path)
                .trimmingCharacters(in: .whitespacesAndNewlines)) ?? "EMPTY"
            let refs = try runGit([
                "for-each-ref",
                "--format=%(objectname) %(refname)",
                "refs/heads",
                "refs/remotes",
                "refs/tags"
            ], in: repository.path)
            let symbolicHead = (try? runGit(["symbolic-ref", "--quiet", "HEAD"], in: repository.path)) ?? ""
            let worktrees = try runGit(["worktree", "list", "--porcelain", "-z"], in: repository.path)

            // Checkouts can move, switch branch or disappear without changing any commit/ref hash.
            return head + "\n" + symbolicHead + "\n" + refs + "\n" + worktrees
        }.value
    }

    func loadChanges(repository: GitRepository, commit: GitCommit, parent: String?) async throws -> CommitChanges {
        try await Task.detached(priority: .userInitiated) {
            // Computing the empty tree rather than hard-coding it also supports SHA-256 repositories.
            let base = try parent ?? runGit(["hash-object", "-t", "tree", "/dev/null"], in: repository.path)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let common = ["diff", "--no-ext-diff", "--no-textconv", "--no-color", "--ignore-submodules=none", "-M"]
            let status = try runGit(common + ["--name-status", "-z", base, commit.hash, "--"], in: repository.path)
            let stats = try runGit(common + ["--numstat", "-z", base, commit.hash, "--"], in: repository.path)
            let message = try runGit(["show", "-s", "--format=%B", commit.hash], in: repository.path)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CommitChanges(baseRevision: base,
                                 files: try GitDiffParser.files(statusOutput: status, statOutput: stats), message: message)
        }.value
    }

    func loadDiff(repository: GitRepository, commit: GitCommit, base: String, file: CommitChangedFile) async throws -> FileDiff {
        try await Task.detached(priority: .userInitiated) {
            var paths = [file.path]
            if let previous = file.previousPath, previous != file.path { paths.insert(previous, at: 0) }
            // Literal pathspecs keep names with brackets, wildcards, or leading colons exact.
            let patch = try runGit([
                "diff", "--no-ext-diff", "--no-textconv", "--no-color", "--ignore-submodules=none", "--submodule=short",
                "--patch", "--raw", "-z", "-M", "--unified=3",
                base, commit.hash, "--"
            ] + paths.map { ":(literal)" + $0 }, in: repository.path)
            return GitDiffParser.diff(try GitDiffParser.patch(for: file.path, in: patch))
        }.value
    }

    private func loadHistorySync(repository: GitRepository) throws -> [CommitRow] {
        let hasCommits = (try? runGit(["rev-parse", "--verify", "HEAD"], in: repository.path)) != nil
        if !hasCommits {
            let refs = try runGit(["for-each-ref", "--count=1", "--format=%(objectname)"], in: repository.path)
            guard !refs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        }

        let arguments = [
            "log",
            "--graph",
            "--all",
            "--decorate=full",
            "--color=always",
            "--date=iso-strict",
            "--format=%x1f%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s%x1f%D"
        ]

        // One walk supplies both metadata and routing. This has the same default
        // ordering and all-ref scope as log --graph --oneline --decorate --all.
        let graphOutput = try runGit(arguments, in: repository.path)
        let metadata = graphOutput.split(separator: "\n").compactMap { line -> String? in
            guard let marker = line.firstIndex(of: "\u{1f}") else { return nil }
            return String(line[line.index(after: marker)...])
        }.joined(separator: "\u{1e}")
        let checkouts = GitWorktreeParser.checkouts(from:
            try runGit(["worktree", "list", "--porcelain", "-z"], in: repository.path))
        let commits = try parseCommits(metadata, checkouts: checkouts)
        return try CommitGraphBuilder().rows(for: commits, graphOutput: graphOutput)
    }

    private func runGit(_ arguments: [String], in directory: URL,
                        environmentOverrides: [String: String] = [:], timeout: TimeInterval? = nil,
                        allowedExitCodes: Set<Int32> = [0]) throws -> String {
        String(decoding: try runGitData(arguments, in: directory, environmentOverrides: environmentOverrides,
                                       timeout: timeout, allowedExitCodes: allowedExitCodes), as: UTF8.self)
    }

    private func runGitData(_ arguments: [String], in directory: URL,
                           environmentOverrides: [String: String] = [:], timeout: TimeInterval? = nil,
                           allowedExitCodes: Set<Int32> = [0]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "diff.autoRefreshIndex=false"] + arguments
        process.currentDirectoryURL = directory
        process.environment = gitProcessEnvironment().merging(environmentOverrides) { _, override in override }

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appending(path: "DonGit-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        let outputURL = temporaryDirectory.appending(path: "stdout")
        let errorURL = temporaryDirectory.appending(path: "stderr")

        guard fileManager.createFile(atPath: outputURL.path, contents: nil),
              fileManager.createFile(atPath: errorURL.path, contents: nil) else {
            throw GitClientError.commandFailed("Unable to create temporary git output files.")
        }

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        let finished = DispatchSemaphore(value: 0)
        if timeout != nil {
            process.terminationHandler = { _ in finished.signal() }
        }
        try process.run()
        if let timeout, finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw GitClientError.commandTimedOut
        }
        process.waitUntilExit()

        let outputData = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorURL)
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        guard allowedExitCodes.contains(process.terminationStatus) else {
            let message = [error, output]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw GitClientError.commandFailed(message.isEmpty ? "Git command failed." : message)
        }

        return outputData
    }

    private func gitProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // Inspection commands must not refresh or lock the user's index as a side effect.
        // Explicit add/commit/fetch commands still take their required locks normally.
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = defaultPath + ":" + path
        } else {
            environment["PATH"] = defaultPath
        }

        return environment
    }

    private func parseCommits(_ output: String, checkouts: [String: GitBranchCheckout]) throws -> [GitCommit] {
        let recordSeparator = Character("\u{1e}")
        let fieldSeparator = Character("\u{1f}")
        let records = output
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return try records.map { record in
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            guard fields.count >= 7 else {
                throw GitClientError.invalidOutput
            }

            return GitCommit(
                hash: String(fields[0]),
                parents: fields[1].split(separator: " ").map(String.init),
                authorName: String(fields[2]),
                authorEmail: String(fields[3]),
                authoredAt: DateParsers.gitDate(String(fields[4])) ?? .distantPast,
                subject: String(fields[5]),
                refs: GitRefParser.badges(from: String(fields[6])).map { badge in
                    var badge = badge
                    if badge.kind == .branch || badge.kind == .currentBranch {
                        badge.checkout = checkouts[badge.name]
                    }
                    return badge
                }
            )
        }
    }
}
