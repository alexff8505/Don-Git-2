import Foundation

@main
struct WorktreeTests {
    @MainActor static func main() async throws {
        var directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DonGit-worktrees-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directory = directory.resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: directory) }

        @discardableResult
        func git(_ arguments: [String], in path: URL) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", path.path, "-c", "user.name=Worktree Test",
                                 "-c", "user.email=worktree@example.test", "-c", "commit.gpgsign=false"] + arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            precondition(process.terminationStatus == 0, text)
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let oddPath = "/tmp/a folder\nwith \"quotes\""
        let parsed = GitWorktreeParser.checkouts(from: [
            "worktree /tmp/bare", "bare", "",
            "worktree " + oddPath, "branch refs/heads/topic", "locked keep this checkout", "",
            "worktree /tmp/stale", "branch refs/heads/stale", "prunable gitdir is missing", "",
            "worktree /tmp/detached", "detached", "", ""
        ].joined(separator: "\0"))
        precondition(parsed.count == 1 && parsed["topic"]?.path == oddPath && parsed["topic"]?.isMain == false,
                     "Preserve unusual paths and locked worktrees; ignore detached and stale entries and bare roots")

        let root = directory.appendingPathComponent("main folder")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "dev"], in: root)
        let rootPath = try git(["rev-parse", "--show-toplevel"], in: root)
        try git(["commit", "--allow-empty", "-qm", "Shared commit"], in: root)
        for branch in ["main", "topic", "other", "moved"] { try git(["branch", branch], in: root) }
        try git(["update-ref", "refs/remotes/origin/topic", "HEAD"], in: root)
        try git(["update-ref", "refs/remotes/upstream/topic", "HEAD"], in: root)
        try git(["tag", "topic"], in: root)
        let repository = GitRepository(path: root, updatedAt: nil)
        let client = GitClient()
        let suite = "DonGit-worktrees-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([root.path], forKey: "repositoryPaths")
        let store = GitViewerStore(defaults: defaults)
        await store.loadInitialData()
        let commitID = store.rows.first!.id
        store.selectedCommitID = commitID
        func badge(_ name: String, _ kind: GitRefBadge.Kind = .branch) -> GitRefBadge? {
            store.rows.flatMap(\.commit.refs).first { $0.name == name && $0.kind == kind }
        }
        precondition(badge("dev", .currentBranch)?.checkout == GitBranchCheckout(path: rootPath, isMain: true))
        precondition(badge("main")?.checkout == nil && badge("topic")?.checkout == nil)

        // Creating a worktree at an existing ref changes no hashes: cached history must still update.
        let linked = directory.appendingPathComponent("linked worktree\nwith newline")
        let before = try await client.historySignature(repository: repository)
        try git(["worktree", "add", "-q", linked.path, "topic"], in: root)
        let linkedPath = try git(["rev-parse", "--show-toplevel"], in: linked)
        let after = try await client.historySignature(repository: repository)
        precondition(before != after)
        await store.refreshAutomatically()
        precondition(badge("topic")?.checkout == GitBranchCheckout(path: linkedPath, isMain: false))
        precondition(badge("main")?.checkout == nil && badge("other")?.checkout == nil,
                     "Sharing the same commit must not imply sharing a checkout")
        precondition(badge("origin/topic", .remote)?.checkout == nil
                     && badge("upstream/topic", .remote)?.checkout == nil && badge("topic", .tag)?.checkout == nil,
                     "Only local branch refs get checkout labels, including with custom remotes and colliding tags")
        precondition(store.selectedCommitID == commitID)

        let linkedRows = try await client.loadHistory(repository: GitRepository(path: linked, updatedAt: nil))
        let linkedBadges = linkedRows.flatMap(\.commit.refs)
        precondition(linkedBadges.first { $0.name == "topic" && $0.kind == .currentBranch }?.checkout?.isMain == false)
        precondition(linkedBadges.first { $0.name == "dev" && $0.kind == .branch }?.checkout?.isMain == true,
                     "The main checkout is determined by Git, not by which folder is being viewed")

        try git(["switch", "-q", "other"], in: linked)
        await store.refreshAutomatically()
        precondition(badge("topic")?.checkout == nil && badge("other")?.checkout?.path == linkedPath)
        let moved = directory.appendingPathComponent("moved worktree")
        try git(["worktree", "move", linked.path, moved.path], in: root)
        let movedPath = try git(["rev-parse", "--show-toplevel"], in: moved)
        await store.refreshAutomatically()
        precondition(badge("other")?.checkout?.path == movedPath)
        try git(["worktree", "remove", moved.path], in: root)
        await store.refreshAutomatically()
        precondition(badge("other")?.checkout == nil)

        try git(["switch", "-q", "main"], in: root)
        await store.refreshAutomatically()
        precondition(badge("dev")?.checkout == nil && badge("main", .currentBranch)?.checkout?.isMain == true,
                     "Switching HEAD between branches at the same commit must refresh badges")
        precondition(store.selectedCommitID == commitID)

        // A missing linked folder is reported as prunable and must not look like a usable checkout.
        let stale = directory.appendingPathComponent("stale")
        try git(["worktree", "add", "-q", stale.path, "moved"], in: root)
        try FileManager.default.removeItem(at: stale)
        await store.refreshAutomatically()
        precondition(badge("moved")?.checkout == nil)

        for path in CommandLine.arguments.dropFirst() {
            let rows = try await client.loadHistory(repository: GitRepository(path: URL(fileURLWithPath: path), updatedAt: nil))
            for badge in rows.flatMap(\.commit.refs) where badge.checkout != nil {
                print("\(badge.name): \(badge.checkout!.label) — \(badge.checkout!.path)")
            }
        }
        print("Passed worktree parsing, branch/ref matching, linked-view identity and cached refresh lifecycle checks.")
    }
}
