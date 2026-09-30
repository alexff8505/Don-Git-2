import Foundation
import AppKit

@main
struct CommitGraphTests {
    static func main() async throws {
        let tests = CommitGraphTests()
        try tests.testMergePreservesGitRoutingAndColors()
        try tests.testRootOnSideLaneDoesNotInterruptOtherLane()
        try tests.testCollapsingLanesShareEndpointsAcrossCommits()
        try tests.testNeutralNodesRetainLaneColors()
        tests.testNativePaletteContrast()
        tests.testHistoryMismatchIsRejected()
        tests.testDecorationOrderMatchesGit()
        try await tests.testRealGitOctopusHistory()
        try await tests.testRealGitInterleavedMergesAndRoots()
        for path in CommandLine.arguments.dropFirst() {
            let rows = try await GitClient().loadHistory(repository: GitRepository(path: URL(fileURLWithPath: path), updatedAt: nil))
            tests.assertRenderedParents(in: rows)
            print("Verified rendered parent connections for \(rows.count) commits in \(path).")
        }
        print("Passed 9 graph checks, including parent topology, lane colour continuity, and native palette contrast.")
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
        assertRenderedParents(in: rows)
    }

    func testRootOnSideLaneDoesNotInterruptOtherLane() throws {
        let commits = [commit("m", parents: ["a", "b"]), commit("b", parents: []), commit("a", parents: [])]
        let rows = try CommitGraphBuilder().rows(for: commits, graphOutput: "* \u{1f}m\n|\\\n| * \u{1f}b\n* \u{1f}a\n")
        precondition(rows[2].graph.incomingColor != nil)
        precondition(rows[1].graph.outgoingColor == nil)
        assertRenderedParents(in: rows)
    }

    func testHistoryMismatchIsRejected() {
        do {
            _ = try CommitGraphBuilder().rows(for: [commit("a", parents: [])], graphOutput: "* \u{1f}b\n")
            preconditionFailure("Mismatched history must be rejected")
        } catch {}
    }

    func testCollapsingLanesShareEndpointsAcrossCommits() throws {
        let commits = [commit("a", parents: ["r"]), commit("b", parents: ["r"]),
                       commit("c", parents: ["r"]), commit("r", parents: [])]
        let rows = try CommitGraphBuilder().rows(for: commits, graphOutput:
            "| | * \u{1f}a\n| * | \u{1f}b\n| |/\n* / \u{1f}c\n|/\n* \u{1f}r\n")
        let before = rows[1].graph
        let collapsing = rows[2].graph
        precondition(String(collapsing.previousLine.map(\.character)) == "| |/")
        precondition(String(before.nextLine.map(\.character)) == "* / ")
        let upperSlash = CommitGraphGeometry.endpoints(
            column: 3, line: before.lines[1], previous: before.lines[0], next: before.nextLine)
        let commitSlash = CommitGraphGeometry.endpoints(
            column: 2, line: collapsing.lines[0], previous: collapsing.previousLine, next: collapsing.lines[1])
        let lowerSlash = CommitGraphGeometry.endpoints(
            column: 1, line: collapsing.lines[1], previous: collapsing.lines[0], next: collapsing.nextLine)
        precondition(upperSlash.lower == 2.5 && upperSlash.lower == commitSlash.upper)
        precondition(commitSlash.lower == 1.5 && commitSlash.lower == lowerSlash.upper)
        let mergingLane = CommitGraphGeometry.endpoints(
            column: 2, line: before.lines[1], previous: before.lines[0], next: before.nextLine)
        precondition(mergingLane.lower == commitSlash.upper)
        precondition(lowerSlash.lower == 0)
    }

    func testDecorationOrderMatchesGit() {
        let refs = GitRefParser.badges(from: "HEAD -> main, origin/main, origin/HEAD, tag: v1")
        precondition(refs.map(\.name) == ["HEAD", "main", "origin/main", "origin/HEAD", "v1"])
        precondition(refs.last?.kind == .tag)
    }

    func testNeutralNodesRetainLaneColors() throws {
        let commits = [commit("m", parents: ["a", "b"]), commit("b", parents: ["b2"]),
            commit("b2", parents: ["r"]), commit("a", parents: ["r"]), commit("r", parents: [])]
        let output = "* \u{1f}m\n\u{1b}[31m|\u{1b}[m\u{1b}[32m\\\u{1b}[m\n"
            + "\u{1b}[31m|\u{1b}[m * \u{1f}b\n\u{1b}[31m|\u{1b}[m * \u{1f}b2\n"
            + "* \u{1b}[32m|\u{1b}[m \u{1f}a\n\u{1b}[31m|\u{1b}[m\u{1b}[32m/\u{1b}[m\n* \u{1f}r\n"
        let rows = try CommitGraphBuilder().rows(for: commits, graphOutput: output)
        precondition(rows[0].graph.outgoingColor == [31])
        for index in [1, 2] {
            precondition(rows[index].graph.incomingColor == [32] && rows[index].graph.outgoingColor == [32],
                         "Neutral commit stars must preserve their incoming lane colour")
        }
        assertRenderedParents(in: rows)
    }

    func testNativePaletteContrast() {
        let codes = (30...37).map { [$0] } + (30...37).map { [1, $0] }
            + (90...97).map { [$0] } + [[38, 5, 226], [38, 2, 255, 255, 0], []]
        for dark in [false, true] {
            for increased in [false, true] {
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
                appearance.performAsCurrentDrawingAppearance {
                    let purple = GitGraphColorPalette.resolvedColor(for: [35], dark: dark, increasedContrast: increased)
                    let brightPurple = GitGraphColorPalette.resolvedColor(for: [1, 35], dark: dark, increasedContrast: increased)
                    precondition(!purple.isEqual(brightPurple), "Normal and bright magenta lanes must remain distinct")
                    for code in codes {
                        let color = GitGraphColorPalette.resolvedColor(for: code, dark: dark, increasedContrast: increased)
                        for background in NSColor.alternatingContentBackgroundColors + [.controlBackgroundColor, .windowBackgroundColor] {
                            precondition(GitGraphColorPalette.contrastRatio(color, background.usingColorSpace(.sRGB)!) >= (increased ? 4.5 : 3),
                                         "Graph colour \(code) has insufficient contrast")
                        }
                    }
                }
            }
        }
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
        assertContinuousEdges(in: rows)
        assertRenderedParents(in: rows)
    }

    func testRealGitInterleavedMergesAndRoots() async throws {
        for initialSeed: UInt64 in [8505, 2026, 7] {
            try await assertInterleavedHistory(initialSeed: initialSeed)
        }
    }

    private func assertInterleavedHistory(initialSeed: UInt64) async throws {
        let fixture = try GraphFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let tree = try fixture.git(["mktree"], input: Data())
        var hashes: [String] = []
        var seed = initialSeed
        for index in 0..<48 {
            var parents: [String] = []
            if index > 0 && index % 17 != 0 {
                seed = seed &* 6364136223846793005 &+ 1
                let count = min(index, Int(seed % 4) + 1)
                var choices: Set<Int> = []
                while choices.count < count {
                    seed = seed &* 6364136223846793005 &+ 1
                    choices.insert(Int((seed >> 32) % UInt64(index)))
                }
                parents = choices.sorted().reversed().map { hashes[$0] }
            }
            var arguments = ["commit-tree", tree, "-m", "Fixture commit \(index)"]
            for parent in parents { arguments += ["-p", parent] }
            let hash = try fixture.git(arguments)
            hashes.append(hash)
            _ = try fixture.git(["update-ref", "refs/heads/fixture-\(index)", hash])
        }
        _ = try fixture.git(["symbolic-ref", "HEAD", "refs/heads/fixture-47"])
        let rows = try await GitClient().loadHistory(repository: GitRepository(path: fixture.directory, updatedAt: nil))
        precondition(rows.count == 48)
        precondition(rows.flatMap(\.graph.lines).contains { $0.contains { $0.character == "_" } },
                     "The fixture must exercise horizontal collapse connectors")
        assertRenderedParents(in: rows)
        let reference = try fixture.git(["log", "--graph", "--oneline", "--decorate", "--all", "--color=never"])
        let expected = reference.split(separator: "\n").filter { $0.contains("*") }.map { line in
            line.drop(while: { "| */\\._-".contains($0) }).split(separator: " ")[0]
        }
        precondition(zip(rows, expected).allSatisfy { $0.commit.hash.hasPrefix($1) },
                     "Native row order must match log --graph --oneline --decorate --all")
    }

    /// Trace the very segments the Canvas draws, stopping at each next commit.
    /// Unlike a boundary-only check, this catches missing octopus stems, false
    /// connections at crossings, dangling routes, and joins to the wrong hash.
    func assertRenderedParents(in rows: [CommitRow]) {
        var adjacency: [GitGraphPoint: Set<GitGraphPoint>] = [:]
        var nodes: [GitGraphPoint: GitCommit] = [:]
        var offset = 0.0
        for row in rows {
            let column = row.graph.lines[row.graph.nodeLine].firstIndex { $0.character == "*" }!
            nodes[GitGraphPoint(column: Double(column), line: offset + Double(row.graph.nodeLine) + 0.5)] = row.commit
            for segment in CommitGraphGeometry.segments(for: row.graph) {
                let start = GitGraphPoint(column: segment.start.column, line: segment.start.line + offset)
                let end = GitGraphPoint(column: segment.end.column, line: segment.end.line + offset)
                adjacency[start, default: []].insert(end)
                if start.line == end.line { adjacency[end, default: []].insert(start) }
            }
            offset += Double(row.graph.lines.count)
        }
        for (node, commit) in nodes {
            var pending = Array(adjacency[node] ?? [])
            var visited: Set<GitGraphPoint> = [node]
            var parents: Set<String> = []
            while let point = pending.popLast() {
                guard visited.insert(point).inserted else { continue }
                if let parent = nodes[point] { parents.insert(parent.hash); continue }
                pending.append(contentsOf: adjacency[point] ?? [])
            }
            precondition(parents == Set(commit.parents),
                         "Rendered parents for \(commit.hash): \(parents), expected \(commit.parents)")
        }
    }

    private func assertContinuousEdges(in rows: [CommitRow]) {
        let lines = rows.flatMap(\.graph.lines)
        for index in 0..<(lines.count - 1) {
            let upper = lines[index]
            let lower = lines[index + 1]
            // Octopus horizontal connectors have separate junction semantics.
            guard !(upper + lower).contains(where: { "._-".contains($0.character) }) else { continue }
            let bottomEndpoints = upper.indices.compactMap {
                CommitGraphGeometry.endpoints(column: $0, line: upper,
                    previous: index > 0 ? lines[index - 1] : [], next: lower).lower
            }
            let topEndpoints = lower.indices.compactMap {
                CommitGraphGeometry.endpoints(column: $0, line: lower,
                    previous: upper, next: index + 2 < lines.count ? lines[index + 2] : []).upper
            }
            precondition(Set(bottomEndpoints) == Set(topEndpoints),
                "Disconnected graph edges between \(String(upper.map(\.character))) and \(String(lower.map(\.character)))")
        }
    }

}

private struct GraphFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DonGit-graph-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = try git(["init", "-q", "-b", "main"])
    }

    func git(_ arguments: [String], input: Data? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path, "-c", "user.name=Graph Test", "-c", "user.email=graph@example.invalid",
                             "-c", "commit.gpgsign=false"] + arguments
        let output = Pipe()
        process.standardOutput = output
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        if let input { stdin.fileHandleForWriting.write(input) }
        try stdin.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
