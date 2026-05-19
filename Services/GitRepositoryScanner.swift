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
                repositories.append(GitRepository(path: url))
                enumerator.skipDescendants()
            }
        }

        return repositories.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
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
