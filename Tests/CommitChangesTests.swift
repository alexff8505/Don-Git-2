import Foundation

@main
struct CommitChangesTests {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DonGit-diff-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func git(_ arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", directory.path, "-c", "user.name=Diff Test", "-c", "user.email=diff@example.test",
                                 "-c", "commit.gpgsign=false"] + arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let result = String(decoding: data, as: UTF8.self)
            precondition(process.terminationStatus == 0, result)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func write(_ name: String, _ contents: String) throws {
            try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        func save(_ subject: String) throws -> String {
            _ = try git(["add", "-A"])
            _ = try git(["commit", "-q", "-m", subject])
            return try git(["rev-parse", "HEAD"])
        }
        _ = try git(["init", "-q", "-b", "main"])
        _ = try git(["config", "core.autocrlf", "false"])
        try write("code.swift", (1...30).map { "let line\($0) = \($0)" }.joined(separator: "\n") + "\n")
        try write("rename me.swift", "one\ntwo\nthree\n")
        try write("deleted.txt", "remove me\n")
        try write("odd\tname\n[é].txt", "before\n")
        try write("[literal].txt", "literal before\n")
        try write("l.txt", "should never match the bracket path\n")
        try Data([0, 1, 2, 3]).write(to: directory.appendingPathComponent("image.bin"))
        let rootHash = try save("Root")
        let client = GitClient()
        let repository = GitRepository(path: directory, updatedAt: nil)
        let root = try await client.loadHistory(repository: repository).first!.commit
        let rootChanges = try await client.loadChanges(repository: repository, commit: root, parent: nil)
        precondition(rootChanges.files.count == 7)
        precondition(rootChanges.files.allSatisfy { $0.status == "A" })
        let rootFile = rootChanges.files.first { $0.path == "code.swift" }!
        let rootDiff = try await client.loadDiff(repository: repository, commit: root, base: rootChanges.baseRevision, file: rootFile)
        precondition(rootDiff.lines.filter { $0.kind == .addition }.count == 30)
        precondition(rootDiff.lines.first { $0.kind == .addition }?.newNumber == 1)

        try write("code.swift", (1...30).map { $0 == 2 || $0 == 27 ? "let edited\($0) = true" : "let line\($0) = \($0)" }.joined(separator: "\n") + "\n")
        try FileManager.default.moveItem(at: directory.appendingPathComponent("rename me.swift"), to: directory.appendingPathComponent("renamed.swift"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("rename me.swift"), withIntermediateDirectories: true)
        try write("rename me.swift/replacement.txt", "A different new file at the old path\n")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("deleted.txt"))
        try write("odd\tname\n[é].txt", "after\n")
        try write("[literal].txt", "literal after\n")
        try write("added.txt", "new file without newline")
        try Data([0, 5, 6]).write(to: directory.appendingPathComponent("image.bin"))
        let changedHash = try save("Changes\n\nFull message body.")
        let changed = try await client.loadHistory(repository: repository).first!.commit
        precondition(changed.hash == changedHash)
        let changes = try await client.loadChanges(repository: repository, commit: changed, parent: rootHash)
        precondition(changes.files.count == 8)
        precondition(changes.message.contains("Full message body."))
        precondition(changes.additions == 6 && changes.deletions == 5)
        let renamed = changes.files.first { $0.path == "renamed.swift" }!
        precondition(renamed.previousPath == "rename me.swift" && renamed.status.first == "R")
        let renameDiff = try await client.loadDiff(repository: repository, commit: changed, base: changes.baseRevision, file: renamed)
        precondition(renameDiff.lines.contains { $0.text.hasPrefix("rename to ") })
        precondition(!renameDiff.lines.contains { $0.kind == .addition })
        precondition(!renameDiff.lines.contains { $0.text.contains("different new file") }, "A rename must not include a replacement at its old path")
        let odd = changes.files.first { $0.path == "odd\tname\n[é].txt" }!
        let oddDiff = try await client.loadDiff(repository: repository, commit: changed, base: changes.baseRevision, file: odd)
        precondition(oddDiff.lines.contains { $0.kind == .addition && $0.text == "after" })
        let literal = changes.files.first { $0.path == "[literal].txt" }!
        let literalDiff = try await client.loadDiff(repository: repository, commit: changed, base: changes.baseRevision, file: literal)
        precondition(literalDiff.lines.contains { $0.text == "literal after" })
        precondition(!literalDiff.lines.contains { $0.text.contains("never match") })
        let binary = changes.files.first { $0.path == "image.bin" }!
        precondition(binary.isBinary)
        let binaryDiff = try await client.loadDiff(repository: repository, commit: changed, base: changes.baseRevision, file: binary)
        precondition(binaryDiff.isBinary)
        let deleted = changes.files.first { $0.path == "deleted.txt" }!
        let deletedDiff = try await client.loadDiff(repository: repository, commit: changed, base: changes.baseRevision, file: deleted)
        precondition(deletedDiff.lines.first { $0.kind == .deletion }?.oldNumber == 1)
        let added = changes.files.first { $0.path == "added.txt" }!
        let addedDiff = try await client.loadDiff(repository: repository, commit: changed, base: changes.baseRevision, file: added)
        precondition(addedDiff.lines.contains { $0.kind == .notice && $0.text.contains("No newline") })
        let code = changes.files.first { $0.path == "code.swift" }!
        let codeDiff = try await client.loadDiff(repository: repository, commit: changed, base: changes.baseRevision, file: code)
        precondition(codeDiff.lines.filter { $0.kind == .hunk }.count == 2)
        precondition(codeDiff.lines.first { $0.kind == .deletion }?.oldNumber == 2)
        precondition(codeDiff.lines.last { $0.kind == .addition }?.newNumber == 27)
        precondition(codeDiff.splitLines.filter { $0.left?.kind == .deletion && $0.right?.kind == .addition }.count == 2)

        _ = try git(["checkout", "-q", "-b", "feature"])
        try write("feature.txt", "feature\n")
        let featureHash = try save("Feature")
        _ = try git(["checkout", "-q", "main"])
        try write("main.txt", "main\n")
        let mainHash = try save("Main")
        _ = try git(["merge", "-q", "--no-ff", "feature", "-m", "Merge"])
        let merge = try await client.loadHistory(repository: repository).first!.commit
        precondition(merge.parents == [mainHash, featureHash])
        let firstParent = try await client.loadChanges(repository: repository, commit: merge, parent: merge.parents[0])
        let secondParent = try await client.loadChanges(repository: repository, commit: merge, parent: merge.parents[1])
        precondition(firstParent.files.map(\.path) == ["feature.txt"])
        precondition(secondParent.files.map(\.path) == ["main.txt"])
        _ = try git(["commit", "-q", "--allow-empty", "-m", "Empty"])
        let empty = try await client.loadHistory(repository: repository).first!.commit
        let emptyChanges = try await client.loadChanges(repository: repository, commit: empty, parent: empty.parents.first)
        precondition(emptyChanges.files.isEmpty)

        let store = CommitChangesStore()
        await store.load(repository: repository, commit: changed, parent: rootHash)
        precondition(store.changes?.files.count == 8 && store.selectedFileID != nil)
        store.selectedFileID = code.path
        await store.loadDiff(repository: repository, commit: changed)
        store.moveChange(1)
        let firstHunk = store.selectedChangeID
        store.moveChange(1)
        precondition(store.selectedChangeID != firstHunk)
        store.moveChange(-1)
        precondition(store.selectedChangeID == firstHunk)
        store.moveFile(1)
        precondition(store.selectedFileID != code.path)
        await store.loadDiff(repository: repository, commit: changed)
        precondition(store.selectedChangeID == nil)
        let olderLoad = Task { await store.load(repository: repository, commit: root, parent: nil) }
        await Task.yield()
        await store.load(repository: repository, commit: merge, parent: merge.parents[1])
        await olderLoad.value
        precondition(store.changes?.files.map(\.path) == ["main.txt"], "Older requests must not replace the latest selection")

        let unbalanced = GitDiffParser.diff("@@ -1,2 +1,3 @@\n-a\n-b\n+x\n+y\n+z\n context\n")
        precondition(unbalanced.splitLines.count == 5)
        precondition(unbalanced.splitLines[3].left == nil && unbalanced.splitLines[3].right?.text == "z")
        precondition(unbalanced.splitLines[4].left?.text == "context" && unbalanced.splitLines[4].right?.text == "context")
        let separateBlocks = GitDiffParser.diff("@@ -1,4 +1,4 @@\n-a\n+x\n context\n-b\n+y\n")
        precondition(separateBlocks.changeIDs.count == 2, "Navigate each change within a single hunk")
        let noNewline = GitDiffParser.diff("@@ -1 +1 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file\n")
        precondition(noNewline.splitLines[1].left?.text == "old" && noNewline.splitLines[1].right?.text == "new")
        precondition(noNewline.splitLines[2].left?.kind == .notice && noNewline.splitLines[2].right?.kind == .notice)
        print("Passed commit changes checks: root, counts, real multi-hunk diff, rename, deletion, addition, binary, unusual/literal paths, merge parents, empty commit, full message, keyboard traversal, stale requests, and side-by-side alignment.")
    }
}
