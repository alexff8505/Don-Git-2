import Foundation

struct GitClient: Sendable {
    enum GitClientError: LocalizedError {
        case commandFailed(String)
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .commandFailed(let message):
                return message
            case .invalidOutput:
                return "Git returned output in an unexpected format."
            }
        }
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
            let output = try runGit(["status", "--porcelain"], in: repository.path)
            return output
                .split(separator: "\n", omittingEmptySubsequences: true)
                .count
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

            return head + "\n" + refs
        }.value
    }

    private func loadHistorySync(repository: GitRepository) throws -> [CommitRow] {
        let hasCommits = (try? runGit(["rev-parse", "--verify", "HEAD"], in: repository.path)) != nil
        guard hasCommits else { return [] }

        let arguments = [
            "log",
            "--all",
            "--topo-order",
            "--decorate=short",
            "--date=iso-strict",
            "--format=%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s%x1f%D%x1e"
        ]

        let output = try runGit(arguments, in: repository.path)
        let commits = try parseCommits(output)
        return CommitGraphBuilder().rows(for: commits)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

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
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        try process.run()
        process.waitUntilExit()

        try? outputHandle.close()
        try? errorHandle.close()

        let outputData = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorURL)
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GitClientError.commandFailed(error.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    private func parseCommits(_ output: String) throws -> [GitCommit] {
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
                refs: GitRefParser.badges(from: String(fields[6]))
            )
        }
    }
}
