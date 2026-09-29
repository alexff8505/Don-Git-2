import Foundation

@main
struct RepositorySelectionTests {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DonGit-selection-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "DonGit-selection-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        func git(_ arguments: [String], in repository: URL) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", repository.path, "-c", "user.name=Selection Test",
                                 "-c", "user.email=selection@example.test", "-c", "commit.gpgsign=false"] + arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            precondition(process.terminationStatus == 0, output)
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func makeRepository(_ name: String) throws -> (URL, [String]) {
            let path = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            _ = try git(["init", "-q", "-b", "main"], in: path)
            var hashes: [String] = []
            for index in 1...3 {
                _ = try git(["commit", "-q", "--allow-empty", "-m", "\(name) commit \(index)"], in: path)
                hashes.append(try git(["rev-parse", "HEAD"], in: path))
            }
            return (path, hashes)
        }

        let (first, firstHashes) = try makeRepository("First")
        let (second, secondHashes) = try makeRepository("Second")
        defaults.set([first.path, second.path], forKey: "repositoryPaths")
        let store = GitViewerStore(defaults: defaults)
        await store.loadInitialData()
        precondition(store.selectedRepositoryID == first.path && store.selectedCommitID == nil)
        store.selectedCommitID = firstHashes[1]
        await store.selectRepository(second.path)
        precondition(store.selectedCommitID == nil, "A new repository should start without a selected commit")
        store.moveCommit(1)
        store.moveCommit(1)
        precondition(store.selectedCommitID == secondHashes[1], "Keyboard navigation must update the remembered selection")
        await store.selectRepository(first.path)
        precondition(store.selectedCommitID == firstHashes[1], "Restore the first repository's selection from cached history")
        await store.selectRepository(second.path)
        precondition(store.selectedCommitID == secondHashes[1], "Each repository must remember its own commit")

        _ = try git(["commit", "-q", "--allow-empty", "-m", "New first commit"], in: first)
        await store.selectRepository(first.path)
        precondition(store.rows.count == 4 && store.selectedCommitID == firstHashes[1],
                     "Restore the same commit after history changes rather than the same row index")
        await store.refreshFromActivation()
        precondition(store.selectedCommitID == firstHashes[1], "Refreshing must preserve the selected commit")

        let olderLoad = Task { await store.selectRepository(second.path) }
        while store.selectedRepositoryID != second.path { await Task.yield() }
        precondition(store.rows.isEmpty, "Clear the old history when switching repositories")
        store.selectedCommitID = firstHashes[0] // Simulate a late selection update from the old table.
        await olderLoad.value
        precondition(store.selectedCommitID == secondHashes[1], "An old table update must not replace the new repository's saved commit")

        let staleLoad = Task { await store.selectRepository(first.path) }
        while store.selectedRepositoryID != first.path { await Task.yield() }
        await store.selectRepository(second.path)
        await staleLoad.value
        precondition(store.selectedRepositoryID == second.path && store.selectedCommitID == secondHashes[1],
                     "An earlier history request must not replace the latest repository or selection")

        let reopened = GitViewerStore(defaults: defaults)
        await reopened.loadInitialData()
        precondition(reopened.selectedRepositoryID == second.path && reopened.selectedCommitID == secondHashes[1],
                     "Restore the selected repository and commit across app launches")
        await reopened.selectRepository(first.path)
        precondition(reopened.selectedCommitID == firstHashes[1], "Other repositories' saved commits must survive reopening")
        await reopened.selectRepository(nil)
        await reopened.selectRepository(first.path)
        precondition(reopened.selectedCommitID == firstHashes[1], "Clearing the active repository must not forget its commit")

        _ = try git(["reset", "--hard", firstHashes[0]], in: first)
        await reopened.refreshFromActivation()
        precondition(reopened.rows.count == 1 && reopened.selectedCommitID == nil,
                     "A commit removed from reachable history must not leave an invalid selection")
        await reopened.selectRepository(second.path)
        await reopened.removeRepository(first.path)
        let saved = defaults.dictionary(forKey: "selectedCommitsByRepository") as? [String: String]
        precondition(saved?[first.path] == nil && saved?[second.path] == secondHashes[1],
                     "Removing a repository should clean up only its remembered selection")
        await reopened.removeRepository(second.path)
        precondition(reopened.selectedRepositoryID == nil && reopened.selectedCommitID == nil && reopened.rows.isEmpty)
        print("Passed repository selection checks: independent commits, keyboard navigation, cached and changed history, refresh, late table updates, rapid switching, relaunch, missing commits, and removal.")
    }
}
