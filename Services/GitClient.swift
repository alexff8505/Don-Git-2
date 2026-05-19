import Foundation

struct GitClient {
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

    func loadHistory(repository: GitRepository, layout: HistoryLayout) async throws -> [CommitRow] {
        var arguments = [
            "log",
            "--all",
            "--decorate=short",
            "--date=iso-strict",
            "--format=%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s%x1f%D%x1e"
        ]
        arguments.insert(contentsOf: layout.gitOrderingArguments, at: 2)

        let output = try runGit(arguments, in: repository.path)
        let commits = try parseCommits(output)
        return CommitGraphBuilder().rows(for: commits)
    }

    func currentBranch(repository: GitRepository) async -> String? {
        try? runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repository.path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

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
