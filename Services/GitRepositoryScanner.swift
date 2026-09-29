import Foundation

struct GitRepositoryScanner {
    func repositories(at paths: [String]) -> [GitRepository] {
        var seenPaths = Set<String>()

        return paths.compactMap { path in
            guard let repository = repository(at: URL(fileURLWithPath: path)),
                  seenPaths.insert(repository.id).inserted else {
                return nil
            }

            return repository
        }
    }

    func repository(at selectedURL: URL) -> GitRepository? {
        let selectedPath = selectedURL.standardizedFileURL.resolvingSymlinksInPath()

        guard let output = try? runGit(["rev-parse", "--show-toplevel"], in: selectedPath)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        let repositoryURL = URL(fileURLWithPath: output)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        return GitRepository(path: repositoryURL, updatedAt: latestCommitDate(in: repositoryURL))
    }

    private func latestCommitDate(in url: URL) -> Date? {
        guard let output = try? runGit(["log", "-1", "--format=%cI"], in: url)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty else {
            return nil
        }

        return DateParsers.gitDate(output)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        // A saved folder can be unavailable (for example, while cloud storage is
        // resolving it). Do not let that folder block the entire repository list.
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            return ""
        }

        guard process.terminationStatus == 0 else {
            return ""
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
