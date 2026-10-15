import Foundation

@main
struct OriginRefreshTests {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DonGit-origin-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "DonGit-origin-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        func expect(_ condition: Bool, _ message: String = "Origin refresh check failed") {
            precondition(condition, message)
        }

        @discardableResult
        func git(_ arguments: [String], in path: URL) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", path.path, "-c", "user.name=Origin Test",
                                 "-c", "user.email=origin@example.test", "-c", "commit.gpgsign=false"] + arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            expect(process.terminationStatus == 0, text)
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func repository(_ name: String) throws -> URL {
            let path = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try git(["init", "-q", "-b", "main"], in: path)
            return path
        }

        let remote = directory.appendingPathComponent("remote.git")
        try git(["init", "--bare", "-q", "-b", "main", remote.path], in: directory)
        let publisher = try repository("publisher")
        try git(["remote", "add", "origin", remote.path], in: publisher)
        try git(["commit", "-q", "--allow-empty", "-m", "Initial commit"], in: publisher)
        try git(["push", "-q", "origin", "main"], in: publisher)
        let first = try git(["rev-parse", "HEAD"], in: publisher)
        let local = directory.appendingPathComponent("viewer")
        try git(["clone", "-q", remote.path, local.path], in: directory)
        // Even a clone configured to fetch one branch must show all origin heads.
        try git(["config", "remote.origin.fetch", "+refs/heads/main:refs/remotes/origin/main"], in: local)
        try git(["config", "fetch.pruneTags", "true"], in: local)
        try git(["config", "remote.origin.pruneTags", "true"], in: local)
        try git(["tag", "local-only-tag"], in: local)
        try git(["commit", "-q", "--allow-empty", "-m", "Remote advance"], in: publisher)
        let second = try git(["rev-parse", "HEAD"], in: publisher)
        try git(["branch", "topic"], in: publisher)
        try git(["push", "-q", "origin", "main", "topic"], in: publisher)
        let dirtyFile = local.appendingPathComponent("uncommitted.txt")
        try "Keep my edits\n".write(to: dirtyFile, atomically: true, encoding: .utf8)
        let statusBefore = try git(["status", "--porcelain"], in: local)

        let noOrigin = try repository("local-only")
        try git(["commit", "-q", "--allow-empty", "-m", "Local only"], in: noOrigin)
        defaults.set([local.path, noOrigin.path], forKey: "repositoryPaths")
        let store = GitViewerStore(defaults: defaults)
        await store.loadInitialData()
        expect(store.originRefreshState.lastChecked != nil && store.originRefreshState.errorMessage == nil)
        expect(try git(["rev-parse", "origin/main"], in: local) == second)
        expect(try git(["rev-parse", "origin/topic"], in: local) == second)
        expect(store.rows.first { $0.id == second }?.commit.refs.contains { $0.name == "origin/main" } == true,
                     "Startup must display the server's branch position")
        expect(try git(["rev-parse", "HEAD"], in: local) == first, "Fetching must not pull local branches")
        expect(try git(["rev-parse", "refs/tags/local-only-tag"], in: local) == first,
               "Background fetching must preserve local tags even when tag pruning is configured")
        expect(try git(["status", "--porcelain"], in: local) == statusBefore)
        expect(try String(contentsOf: dirtyFile, encoding: .utf8) == "Keep my edits\n")
        store.selectedCommitID = first

        // Polling should retain ten-second local updates without fetching more than once a minute.
        let checkedAt = store.originRefreshState.lastChecked
        try git(["branch", "later"], in: publisher)
        try git(["push", "-q", "origin", "later"], in: publisher)
        await store.refreshAutomatically()
        expect(store.originRefreshState.lastChecked == checkedAt)
        expect(!store.rows.flatMap(\.commit.refs).contains { $0.name == "origin/later" })
        await store.refreshFromActivation()
        expect(store.rows.flatMap(\.commit.refs).contains { $0.name == "origin/later" },
                     "Manual refresh and activation must bypass the polling interval")
        expect(store.selectedCommitID == first, "Remote refresh must preserve selection")

        // Force-push one head and delete another, including its remote-only commit.
        try git(["reset", "--hard", first], in: publisher)
        try git(["push", "-q", "--force", "origin", "main", ":topic", ":later"], in: publisher)
        await store.refreshFromActivation()
        expect(try git(["rev-parse", "origin/main"], in: local) == first)
        expect(!store.rows.flatMap(\.commit.refs).contains { $0.name == "origin/topic" })
        expect(!store.rows.contains { $0.id == second }, "Pruning must remove unreachable remote-only history")

        let successfulCheck = store.originRefreshState.lastChecked
        try git(["remote", "set-url", "origin", directory.appendingPathComponent("unavailable.git").path], in: local)
        await store.refreshFromActivation()
        expect(store.originRefreshState.errorMessage != nil && store.originRefreshState.lastChecked == successfulCheck)
        expect(store.errorMessage == nil && store.rows.contains { $0.id == first },
                     "An unreachable origin must leave local history available")
        await store.selectRepository(noOrigin.path)
        expect(store.originRefreshState.hasOrigin == false && store.originRefreshState.errorMessage == nil)
        expect(store.rows.count == 1, "Repositories without origin must work normally")
        try git(["remote", "set-url", "origin", remote.path], in: local)
        await store.selectRepository(local.path)
        expect(store.originRefreshState.errorMessage == nil && store.originRefreshState.lastChecked != nil,
                     "Reopening the repository must retry and clear a prior failure")

        let unborn = try repository("unborn")
        try git(["remote", "add", "origin", remote.path], in: unborn)
        let client = GitClient()
        _ = try await client.fetchOrigin(repository: GitRepository(path: unborn, updatedAt: nil))
        let remoteRows = try await client.loadHistory(repository: GitRepository(path: unborn, updatedAt: nil))
        expect(remoteRows.contains { $0.id == first }, "Remote history must work before a local HEAD exists")

        // A slow upload-pack gives activation and selection time to overlap a real fetch.
        let helper = directory.appendingPathComponent("upload-pack")
        let calls = directory.appendingPathComponent("fetch-calls")
        try "#!/bin/sh\necho fetch >> '\(calls.path)'\nsleep 1\nexec /usr/bin/git-upload-pack \"$@\"\n"
            .write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        try git(["config", "remote.origin.uploadpack", helper.path], in: local)
        let firstRefresh = Task { await store.refreshFromActivation() }
        while !store.originRefreshState.isRefreshing { await Task.yield() }
        expect(!store.rows.isEmpty, "A slow fetch must not hide the graph")
        let overlappingRefresh = Task { await store.refreshFromActivation() }
        await firstRefresh.value
        await overlappingRefresh.value
        let fetchCalls = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n")
        expect(fetchCalls.count == 1, "Overlapping refreshes must share one fetch")
        let switchingRefresh = Task { await store.refreshFromActivation() }
        while !store.originRefreshState.isRefreshing { await Task.yield() }
        await store.selectRepository(noOrigin.path)
        await switchingRefresh.value
        expect(store.selectedRepositoryID == noOrigin.path && store.originRefreshState.hasOrigin == false)
        expect(store.rows.count == 1 && store.rows.first?.commit.subject == "Local only",
                     "A late fetch must not replace another repository's history or status")

        let started = Date()
        do {
            _ = try await client.fetchOrigin(repository: GitRepository(path: local, updatedAt: nil), timeout: 0.1)
            preconditionFailure("A slow fetch must time out")
        } catch GitClient.GitClientError.commandTimedOut {
            expect(Date().timeIntervalSince(started) < 3)
        }
        expect(try git(["rev-parse", "HEAD"], in: local) == first)
        expect(try git(["status", "--porcelain"], in: local) == statusBefore)
        print("Passed origin checks: remote advances, all heads, polling interval, forced refresh, force-pushes, pruning, local changes, offline history, recovery, missing origin, unborn HEAD, overlapping fetches, repository switching, and timeout.")
    }
}
