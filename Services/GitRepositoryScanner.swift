import Foundation

struct GitRepositoryScanner {
    var sitesURL: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Sites")

    func repositories() -> [GitRepository] {
        guard let enumerator = FileManager.default.enumerator(
            at: sitesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var repositories: [GitRepository] = []

        for case let url as URL in enumerator {
            guard isDirectory(url) else { continue }

            if shouldSkipChildren(of: url) {
                enumerator.skipDescendants()
                continue
            }

            if isGitRepository(url) {
                repositories.append(GitRepository(path: url, updatedAt: latestCommitDate(in: url)))
                enumerator.skipDescendants()
            }
        }

        return repositories.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
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

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return ""
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func isGitRepository(_ url: URL) -> Bool {
        let gitPath = url.appending(path: ".git").path
        return FileManager.default.fileExists(atPath: gitPath)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func shouldSkipChildren(of url: URL) -> Bool {
        let name = url.lastPathComponent
        return name == "node_modules"
            || name == ".build"
            || name == "DerivedData"
            || name == "vendor"
            || name == "Pods"
    }
}
