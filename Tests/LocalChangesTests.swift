import Foundation

@main
struct LocalChangesTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DonGit-local-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "DonGit-local-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        func expect(_ condition: Bool, _ message: String = "Local changes check failed") {
            precondition(condition, message)
        }
        @discardableResult
        func git(_ arguments: [String], in directory: URL = root, allowed: Set<Int32> = [0]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", directory.path, "-c", "user.name=Local Test", "-c", "user.email=local@example.test",
                                 "-c", "commit.gpgsign=false"] + arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            expect(allowed.contains(process.terminationStatus), output)
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func write(_ path: String, _ text: String, in directory: URL = root) throws {
            let url = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try git(["init", "-q", "-b", "main"])
        try write("code.swift", "let value = 1\n")
        try write("rename me.swift", "one\ntwo\nthree\n")
        try write("deleted.txt", "delete me\n")
        try write("cancelled.txt", "original\n")
        try write("recreated.txt", "original file\n")
        try write("clean.txt", "unchanged content\n")
        try write("odd\tname\n[é].txt", "before\n")
        try write(".gitignore", "ignored/\n")
        try Data([0, 1, 2]).write(to: root.appendingPathComponent("binary.bin"))
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", "Baseline"])
        let head = try git(["rev-parse", "HEAD"])
        let repository = GitRepository(path: root, updatedAt: nil)
        let client = GitClient()
        expect(try await client.localChangesCount(repository: repository) == 0)

        try write("code.swift", "let value = 2\n")
        try git(["add", "code.swift"])
        try write("code.swift", "let value = 3\n")
        try write("cancelled.txt", "staged version\n")
        try git(["add", "cancelled.txt"])
        try write("cancelled.txt", "original\n")
        try git(["mv", "rename me.swift", "renamed.swift"])
        try write("rename me.swift/replacement.txt", "replacement at the old path\n")
        try FileManager.default.removeItem(at: root.appendingPathComponent("deleted.txt"))
        try git(["rm", "-q", "recreated.txt"])
        try write("recreated.txt", "recreated content\n")
        try write("odd\tname\n[é].txt", "after\n")
        try write("new/nested.txt", "new line\nsecond line\n")
        try write("new/empty.txt", "")
        try write(":literal[é].txt", "literal new file\n")
        try write("ignored/private.txt", "ignored content\n")
        try Data([0, 5, 6]).write(to: root.appendingPathComponent("binary.bin"))
        try Data([0, 8]).write(to: root.appendingPathComponent("new/binary.bin"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("new/link").path,
                                                 withDestinationPath: "../code.swift")
        let indexBefore = try Data(contentsOf: root.appendingPathComponent(".git/index"))
        // A changed stat with unchanged contents must not become a phantom changed file.
        try write("clean.txt", "unchanged content\n")
        let changes = try await client.loadWorkingTreeChanges(repository: repository)
        expect(try Data(contentsOf: root.appendingPathComponent(".git/index")) == indexBefore,
               "Loading the working-tree file list must not write the index")
        expect(changes.baseRevision == head && changes.baseLabel == "HEAD")
        expect(try await client.localChangesCount(repository: repository) == changes.files.count,
               "The row count must count every untracked file, preserve NUL paths, and deduplicate recreated paths")
        expect(!changes.files.contains { $0.path.hasPrefix("ignored/") })
        expect(!changes.files.contains { $0.path == "clean.txt" })
        func file(_ path: String) -> CommitChangedFile { changes.files.first { $0.path == path }! }
        expect(file("renamed.swift").previousPath == "rename me.swift")
        expect(file("new/nested.txt").additions == 2)
        expect(file(":literal[é].txt").additions == 1 && file(":literal[é].txt").deletions == 0)
        expect(file("new/empty.txt").additions == 0 && !file("new/empty.txt").isBinary)
        expect(file("new/binary.bin").isBinary && file("binary.bin").isBinary)
        expect(file("deleted.txt").status == "D")
        expect(file("recreated.txt").status == "M" && file("recreated.txt").deletions == 1)
        expect(file("cancelled.txt").status == "S")
        let diff = try await client.loadWorkingTreeDiff(repository: repository, base: head, file: file("code.swift"))
        expect(try Data(contentsOf: root.appendingPathComponent(".git/index")) == indexBefore,
               "Loading a tracked diff must not write the index")
        expect(diff.lines.contains { $0.kind == .addition && $0.text == "let value = 3" }, "Use the current working copy")
        expect(!diff.lines.contains { $0.text == "let value = 2" }, "Do not stop at the staged snapshot")
        let renameDiff = try await client.loadWorkingTreeDiff(repository: repository, base: head, file: file("renamed.swift"))
        expect(try Data(contentsOf: root.appendingPathComponent(".git/index")) == indexBefore,
               "Loading a renamed diff must not write the index")
        expect(renameDiff.lines.contains { $0.text.hasPrefix("rename to ") })
        expect(!renameDiff.lines.contains { $0.text.contains("replacement at the old path") })
        for path in ["new/nested.txt", ":literal[é].txt", "odd\tname\n[é].txt", "new/link", "recreated.txt"] {
            let preview = try await client.loadWorkingTreeDiff(repository: repository, base: head, file: file(path))
            expect(try Data(contentsOf: root.appendingPathComponent(".git/index")) == indexBefore,
                   "Loading \(path) must not write the index")
            expect(preview.lines.contains { $0.kind == .addition }, "Missing diff for \(path)")
        }
        let staged = try await client.loadWorkingTreeDiff(repository: repository, base: head, file: file("cancelled.txt"))
        expect(staged.lines.contains { $0.text.contains("still has staged changes") })
        let binary = try await client.loadWorkingTreeDiff(repository: repository, base: head, file: file("new/binary.bin"))
        expect(binary.isBinary)
        expect(try Data(contentsOf: root.appendingPathComponent(".git/index")) == indexBefore,
               "Reviewing changes must leave the real index byte-for-byte unchanged")
        expect(try git(["rev-parse", "HEAD"]) == head)

        let details = CommitChangesStore()
        await details.load(repository: repository, commit: nil)
        details.selectedFileID = "code.swift"
        await details.loadDiff(repository: repository, commit: nil)
        details.moveChange(1)
        let selectedChange = details.selectedChangeID
        await details.load(repository: repository, commit: nil)
        await details.loadDiff(repository: repository, commit: nil)
        expect(details.selectedFileID == "code.swift" && details.selectedChangeID == selectedChange,
               "Unchanged background refreshes must preserve the selected file and change")
        try write("code.swift", "let value = 4\n")
        await details.load(repository: repository, commit: nil)
        await details.loadDiff(repository: repository, commit: nil)
        expect(details.selectedFileID == "code.swift" && details.diff?.lines.contains { $0.text == "let value = 4" } == true,
               "Same-file edits must refresh even when file count and Git status do not change")

        defaults.set([root.path], forKey: "repositoryPaths")
        let viewer = GitViewerStore(defaults: defaults)
        await viewer.loadInitialData()
        expect(viewer.historyEntries.first?.id == HistoryEntry.workingTreeID && viewer.isShowingLocalChanges)
        expect(viewer.rows.count == 1 && viewer.rows.first?.id == head, "Working tree must never become a fake commit")
        viewer.moveCommit(1)
        expect(viewer.selectedCommitID == head)
        viewer.moveCommit(-1)
        expect(viewer.isShowingLocalChanges, "Keyboard navigation must include the local changes row")
        let reopened = GitViewerStore(defaults: defaults)
        await reopened.loadInitialData()
        expect(reopened.isShowingLocalChanges, "Remember the working-tree selection across launches")
        await reopened.commitAllChanges(message: "Commit reviewed edits")
        expect(reopened.localChangesCount == 0 && !reopened.isShowingLocalChanges && reopened.rows.count == 2,
               "After committing, remove the synthetic row and select the actual new HEAD")
        expect(reopened.selectedCommitID == (try git(["rev-parse", "HEAD"])))

        let unborn = root.appendingPathComponent("unborn")
        try FileManager.default.createDirectory(at: unborn, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"], in: unborn)
        try write("first.txt", "first file\n", in: unborn)
        let unbornRepository = GitRepository(path: unborn, updatedAt: nil)
        let firstChanges = try await client.loadWorkingTreeChanges(repository: unbornRepository)
        expect(firstChanges.files.count == 1 && firstChanges.baseLabel == "Empty tree")
        let firstDiff = try await client.loadWorkingTreeDiff(repository: unbornRepository,
            base: firstChanges.baseRevision, file: firstChanges.files[0])
        expect(firstDiff.lines.contains { $0.kind == .addition && $0.text == "first file" })
        try await reopened.addRepository(at: unborn)
        expect(reopened.rows.isEmpty && reopened.historyEntries.count == 1 && reopened.isShowingLocalChanges,
               "An unborn repository must display its uncommitted changes instead of an empty-history screen")
        try git(["add", "first.txt"], in: unborn)
        let stagedFirst = try await client.loadWorkingTreeChanges(repository: unbornRepository)
        expect(stagedFirst.files.first?.status == "A")

        // A genuine merge conflict remains inspectable rather than failing the file parser.
        try git(["checkout", "-q", "-b", "conflict-side"])
        try write("code.swift", "side version\n")
        try git(["add", "code.swift"])
        try git(["commit", "-q", "-m", "Side"])
        try git(["checkout", "-q", "main"])
        try write("code.swift", "main version\n")
        try git(["add", "code.swift"])
        try git(["commit", "-q", "-m", "Main"])
        try git(["merge", "conflict-side"], allowed: [1])
        let conflicted = try await client.loadWorkingTreeChanges(repository: repository)
        let conflict = conflicted.files.first { $0.path == "code.swift" }!
        expect(conflict.status == "U")
        let conflictDiff = try await client.loadWorkingTreeDiff(repository: repository, base: conflicted.baseRevision, file: conflict)
        expect(conflictDiff.lines.contains { $0.text.hasPrefix("<<<<<<<") })
        print("Passed local changes checks: staged/unstaged edits, new and ignored files, binary and empty files, symlinks, NUL-safe paths, renames, deletions, recreated paths, preserved index, live refresh, selection, committing, unborn HEAD, and conflicts.")
    }
}
