import Foundation

@main
struct CommitGraphTests {
    static func main() async throws {
        let tests = CommitGraphTests()
        try tests.testMergePreservesGitRoutingAndColors()
        try tests.testRootOnSideLaneDoesNotInterruptOtherLane()
        tests.testHistoryMismatchIsRejected()
        tests.testDecorationOrderMatchesGit()
        try await tests.testRealGitOctopusHistory()
        print("Passed 5 graph checks, including a real Git octopus merge.")
    }

    private func commit(_ hash: String, parents: [String]) -> GitCommit {
        GitCommit(hash: hash, parents: parents, authorName: "Test", authorEmail: "",
                  authoredAt: .distantPast, subject: hash, refs: [])
    }

    func testMergePreservesGitRoutingAndColors() throws {
        let commits = [commit("m", parents: ["a", "b"]), commit("b", parents: ["r"]),
                       commit("a", parents: ["r"]), commit("r", parents: [])]
        let output = "* \u{1f}m\n\u{1b}[31m|\u{1b}[m\u{1b}[32m\\\u{1b}[m  \n\u{1b}[31m|\u{1b}[m * \u{1f}b\n* \u{1b}[32m|\u{1b}[m \u{1f}a\n\u{1b}[31m|\u{1b}[m\u{1b}[32m/\u{1b}[m  \n* \u{1f}r\n"
        let rows = try CommitGraphBuilder().rows(for: commits, graphOutput: output)
        precondition(rows.map(\.commit.hash) == ["m", "b", "a", "r"])
        precondition(rows[0].graph.lines.map { String($0.map(\.character)) } == ["* ", "|\\  "])
        precondition(rows[1].graph.lines[0].firstIndex { $0.character == "*" } == 2)
        precondition(rows[1].graph.incomingColor == [32])
        precondition(rows[2].graph.lines.map { String($0.map(\.character)) } == ["* | ", "|/  "])
        precondition(rows[0].graph.incomingColor == nil)
        precondition(rows.last?.graph.outgoingColor == nil)
    }

    func testRootOnSideLaneDoesNotInterruptOtherLane() throws {
        let commits = [commit("m", parents: ["a", "b"]), commit("b", parents: []), commit("a", parents: [])]
        let rows = try CommitGraphBuilder().rows(for: commits, graphOutput: "* \u{1f}m\n|\\\n| * \u{1f}b\n* \u{1f}a\n")
        precondition(rows[2].graph.incomingColor != nil)
        precondition(rows[1].graph.outgoingColor == nil)
    }

    func testHistoryMismatchIsRejected() {
        do {
            _ = try CommitGraphBuilder().rows(for: [commit("a", parents: [])], graphOutput: "* \u{1f}b\n")
            preconditionFailure("Mismatched history must be rejected")
        } catch {}
    }

    func testDecorationOrderMatchesGit() {
        let refs = GitRefParser.badges(from: "HEAD -> main, origin/main, origin/HEAD, tag: v1")
        precondition(refs.map(\.name) == ["HEAD", "main", "origin/main", "origin/HEAD", "v1"])
        precondition(refs.last?.kind == .tag)
    }
    func testRealGitOctopusHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func git(_ arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", directory.path] + arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            precondition(process.terminationStatus == 0)
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = try git(["init", "-q", "-b", "main"])
        _ = try git(["config", "user.name", "Test"])
        _ = try git(["config", "user.email", "test@example.invalid"])
        _ = try git(["commit", "--allow-empty", "-qm", "root"])
        let root = try git(["rev-parse", "HEAD"])
        let tree = try git(["rev-parse", "HEAD^{tree}"])
        let parents = try (0..<4).map { index in
            try git(["commit-tree", tree, "-p", root, "-m", "branch \(index)"])
        }
        var arguments = ["commit-tree", tree, "-m", "octopus"]
        for parent in parents { arguments += ["-p", parent] }
        let merge = try git(arguments)
        _ = try git(["update-ref", "refs/heads/main", merge])
        let rows = try await GitClient().loadHistory(repository: GitRepository(path: directory, updatedAt: nil))
        precondition(rows.count == 6)
        precondition(rows.first?.commit.hash == merge)
        precondition(rows.first?.graph.lines.first?.contains { $0.character == "." } == true)
        precondition(rows.first?.graph.laneCount == 4)
        precondition(rows.last?.commit.hash == root)
        let plain = try git(["log", "--all", "--graph", "--topo-order", "--color=never", "--format=%x1f%H"])
        let expected = plain.split(separator: "\n").map { String($0.split(separator: "\u{1f}", omittingEmptySubsequences: false)[0]).trimmingCharacters(in: .whitespaces) }
        let actual = rows.flatMap(\.graph.lines).map { String($0.map(\.character)).trimmingCharacters(in: .whitespaces) }
        precondition(actual == expected)
    }

}
