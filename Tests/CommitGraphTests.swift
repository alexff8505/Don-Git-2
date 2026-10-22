import Foundation
import AppKit

@main
struct CommitGraphTests {
    static func main() async throws {
        let tests = CommitGraphTests()
        tests.testNativeRowSpansMeetAcrossSpacing()
        try tests.testMergePreservesGitRoutingAndColors()
        try tests.testRootOnSideLaneDoesNotInterruptOtherLane()
        try tests.testCollapsingLanesShareEndpointsAcrossCommits()
        try tests.testNeutralNodesRetainLaneColors()
        try tests.testDistinctMergePathColors()
        try tests.testThreeParentMergeWithDuplicateLane()
        tests.testNativePaletteContrast()
        tests.testHistoryMismatchIsRejected()
        tests.testDecorationOrderMatchesGit()
        try tests.testWorkingTreeConnectionBypassesNewerCommits()
        tests.testRefGroupsPairLocalAndRemoteBranches()
        try await tests.testRealGitOctopusHistory()
        try await tests.testRealGitInterleavedMergesAndRoots()
        for path in CommandLine.arguments.dropFirst() {
            let rows = try await GitClient().loadHistory(repository: GitRepository(path: URL(fileURLWithPath: path), updatedAt: nil))
            tests.assertRenderedParents(in: rows)
            print("Verified rendered parent connections for \(rows.count) commits in \(path).")
        }
        print("Passed 14 graph checks, including native row spacing, working-tree connections, ref pairs, three-parent duplicate lanes, parent topology, distinct merge paths, lane colour continuity, and native palette contrast.")
    }

    func testNativeRowSpansMeetAcrossSpacing() {
        for spacing: CGFloat in [0, 2, 7, 13] {
            let rects = [42.0, 72, 42, 108].reduce(into: [CGRect]()) { result, height in
                result.append(CGRect(x: 0, y: result.last.map { $0.maxY + spacing } ?? 0, width: 100, height: height))
            }
            let spans = rects.indices.map { index in
                CommitGraphRowSpan(row: rects[index], previous: index > 0 ? rects[index - 1] : nil,
                                   next: index + 1 < rects.count ? rects[index + 1] : nil)
            }
            precondition(spans[0].top == rects[0].minY && spans.last!.bottom == rects.last!.maxY)
            for index in 1..<spans.count {
                precondition(spans[index - 1].bottom == spans[index].top,
                             "Graph rows must meet across native spacing, regardless of merge row height")
                let independentlyVisible = CommitGraphRowSpan(row: rects[index], previous: rects[index - 1],
                    next: index + 1 < rects.count ? rects[index + 1] : nil)
                precondition(independentlyVisible.top == spans[index - 1].bottom,
                             "Scrolling a neighbour offscreen must not change the shared boundary")
                precondition(spans[index].top < rects[index].midY && spans[index].bottom > rects[index].midY)
            }
        }
    }

    private func commit(_ hash: String, parents: [String]) -> GitCommit {
        GitCommit(hash: hash, parents: parents, authorName: "Test", authorEmail: "",
                  authoredAt: .distantPast, subject: hash, refs: [])
    }

    func testWorkingTreeConnectionBypassesNewerCommits() throws {
        let newer = commit("newer", parents: ["middle"])
        let middle = commit("middle", parents: ["head"])
        let head = GitCommit(hash: "head", parents: ["root"], authorName: "Test", authorEmail: "",
                             authoredAt: .distantPast, subject: "HEAD", refs: GitRefParser.badges(from: "HEAD -> dev"))
        let root = commit("root", parents: [])
        let rows = try CommitGraphBuilder().rows(for: [newer, middle, head, root],
            graphOutput: "* \u{1f}newer\n* \u{1f}middle\n* \u{1f}head\n* \u{1f}root\n")
        let layout = WorkingTreeGraphLayout(rows: rows, hasLocalChanges: true)
        precondition(layout.graphInset == 16, "Reserve a lane so the dotted stem does not pass through unrelated nodes")
        precondition(layout.connections == ["newer": .continuation, "middle": .continuation, "head": .head],
                     "Continue through every intervening row, terminate at actual HEAD, and stop before its parents")
        let direct = WorkingTreeGraphLayout(rows: Array(rows.dropFirst(2)), hasLocalChanges: true)
        precondition(direct.graphInset == 0 && direct.connections == ["head": .head])
        let clean = WorkingTreeGraphLayout(rows: rows, hasLocalChanges: false)
        precondition(clean.connections.isEmpty && clean.graphInset == 0)
        let noHead = WorkingTreeGraphLayout(rows: [rows[0]], hasLocalChanges: true)
        precondition(noHead.connections.isEmpty && noHead.graphInset == 0,
                     "Unborn repositories or history without HEAD must not connect to another branch")
        let empty = WorkingTreeGraphLayout(rows: [], hasLocalChanges: true)
        precondition(empty.connections.isEmpty && empty.graphInset == 0)
        let detached = GitCommit(hash: "detached", parents: [], authorName: "Test", authorEmail: "",
                                authoredAt: .distantPast, subject: "Detached", refs: GitRefParser.badges(from: "HEAD"))
        let detachedRows = try CommitGraphBuilder().rows(for: [detached], graphOutput: "* \u{1f}detached\n")
        precondition(WorkingTreeGraphLayout(rows: detachedRows, hasLocalChanges: true).connections == ["detached": .head])
    }

    func testRefGroupsPairLocalAndRemoteBranches() {
        var badges = GitRefParser.badges(from:
            "HEAD -> dev, origin/main, origin/dev, origin/HEAD, tag: v1, main, origin/codex/topic, codex/topic, origin/only-remote")
        let checkout = GitBranchCheckout(path: "/tmp/topic", isMain: false)
        badges[badges.firstIndex { $0.name == "codex/topic" }!].checkout = checkout
        badges.append(GitRefBadge(name: "upstream/codex/topic", kind: .remote))
        let groups = GitRefParser.groups(for: badges)
        precondition(groups.map { $0.badges.map(\.name) } == [
            ["dev", "origin/dev"], ["codex/topic", "origin/codex/topic", "upstream/codex/topic"],
            ["main", "origin/main"], ["origin/HEAD"], ["v1"], ["origin/only-remote"]
        ], "Keep HEAD first, pair exact branch names (including slashes), and leave tags/symbolic refs separate")
        precondition(groups[1].badges[0].checkout == checkout, "Checkout metadata stays with the local pill")
        let visibleIDs = groups.flatMap(\.badges).map(\.id)
        precondition(Set(visibleIDs).count == badges.count - 1 && visibleIDs.count == badges.count - 1,
                     "Only the redundant HEAD pill is hidden; each other badge appears once")
        let unpaired = GitRefParser.groups(for: [GitRefBadge(name: "dev", kind: .branch),
                                                GitRefBadge(name: "origin/main", kind: .remote)])
        precondition(unpaired.map { $0.badges.map(\.name) } == [["dev"], ["origin/main"]],
                     "A remote on another commit must not be invented or paired with a different branch")
        precondition(GitRefParser.groups(for: GitRefParser.badges(from: "HEAD, origin/main")).first?.badges.first?.kind == .head)
        precondition(GitRefParser.groups(for: []).isEmpty)
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

    func testDistinctMergePathColors() throws {
        let commits = [commit("main", parents: ["merge", "dev"]),
            commit("dev", parents: ["pdf", "topic"]), commit("pdf", parents: ["older"]),
            commit("merge", parents: ["older", "topic"]), commit("topic", parents: ["root"]),
            commit("older", parents: ["root"]), commit("root", parents: [])]
        let lines: [(String, String?)] = [("*", "main"), ("|\\", nil), ("| *", "dev"),
            ("| |\\", nil), ("| * |", "pdf"), ("* | |", "merge"), ("|\\ \\ \\", nil),
            ("| |/ /", nil), ("|/| /", nil), ("| |/", nil), ("| *", "topic"),
            ("* |", "older"), ("|/", nil), ("*", "root")]
        // Reproduce Git's all-blue merge routing from avail-admin d105896.
        let output = lines.map { prefix, hash in
            "\u{1b}[34m" + prefix + "\u{1b}[m" + (hash.map { " \u{1f}" + $0 } ?? "")
        }.joined(separator: "\n")
        let raw = try CommitGraphBuilder().rows(for: commits, graphOutput: output)
        let rows = CommitGraphColors.apply(to: raw)
        precondition(rows == CommitGraphColors.apply(to: raw), "Path colours must be deterministic")
        let merge = rows[3].graph.pathSegments!
        let entries = merge.filter { $0.start.line == 0 }.map(\.color)
        precondition(entries.count == 3 && Set(entries).count == 3,
                     "All three incoming paths must retain distinct colours through the merge")
        let parentBranch = merge.first { $0.start == GitGraphPoint(column: 0, line: 1)
            && $0.end == GitGraphPoint(column: 2, line: 2) }!
        precondition(!entries.contains(parentBranch.color), "The extra parent needs its own colour")
        for row in rows[1...3] {
            precondition(row.graph.displayNodeColor == row.graph.pathSegments!.first {
                $0.end == GitGraphPoint(column: Double(row.graph.lines[0].firstIndex { $0.character == "*" }!), line: 0.5)
            }?.color, "Commit nodes must inherit their incoming path colour")
        }
        assertRenderedParents(in: raw)
    }

    func testThreeParentMergeWithDuplicateLane() throws {
        let commits = [commit("merge", parents: ["first", "second", "third"]),
            commit("second", parents: []), commit("passingRight", parents: []),
            commit("first", parents: []), commit("passingLeft", parents: []), commit("third", parents: [])]
        // Reduced from the failing dense history. The vertical lane beside the
        // new '\\' duplicates an existing parent on its left, while the new
        // lane immediately collapses. Git can give both the same ANSI colour.
        let lines: [(String, String?)] = [("| | | | | *", "merge"), ("| | | |_|/|\\", nil),
            ("| | |/| |/", nil), ("| |_|_|/|", nil), ("|/| | | |", nil),
            ("| | | | *", "second"), ("| | | *", "passingRight"),
            ("| | *", "first"), ("| *", "passingLeft"), ("*", "third")]
        let output = lines.map { prefix, hash in
            "\u{1b}[32m" + prefix + "\u{1b}[m" + (hash.map { " \u{1f}" + $0 } ?? "")
        }.joined(separator: "\n")
        let rows = try CommitGraphBuilder().rows(for: commits, graphOutput: output)
        assertRenderedParents(in: rows)
        // If more collapsing lanes follow on the right (an octopus merge),
        // the middle slash must still connect to the vertical above it.
        func line(_ text: String) -> [GitGraphGlyph] {
            text.map { GitGraphGlyph(character: $0, color: [32]) }
        }
        let expanded = line("|/|\\ \\")
        let collapsing = line("|/ / /")
        let slash = CommitGraphGeometry.endpoints(column: 1, line: collapsing, previous: expanded, next: [])
        let vertical = CommitGraphGeometry.endpoints(column: 2, line: expanded, previous: [], next: collapsing)
        precondition(slash.upper == 2 && vertical.lower == 2,
                     "Continuing octopus expansion must not be mistaken for a duplicate parent")
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
        assertRenderedParents(in: rows, smoothed: false)
        let colored = CommitGraphColors.apply(to: rows)
        assertPathColors(in: colored)
        assertRenderedParents(in: colored, smoothed: true)
    }

    private func assertPathColors(in rows: [CommitRow]) {
        var boundary: [Double: [Int]] = [:]
        for row in rows {
            let segments = row.graph.pathSegments!
            precondition(segments.count == CommitGraphGeometry.segments(for: row.graph).count)
            var incoming: [GitGraphPoint: [[Int]]] = [:]
            var outgoing: [GitGraphPoint: [[Int]]] = [:]
            for segment in segments {
                let reverse = segment.start.line == segment.end.line && segment.start.line.rounded() == segment.start.line
                let start = reverse ? segment.end : segment.start
                let end = reverse ? segment.start : segment.end
                incoming[end, default: []].append(segment.color)
                outgoing[start, default: []].append(segment.color)
                if start.line == 0, let previous = boundary[start.column] {
                    precondition(segment.color == previous, "Path colour changed between commit rows")
                }
            }
            for (point, colors) in outgoing {
                if colors.count > 1 {
                    precondition(Set(colors).count == colors.count, "Separate parent paths must have distinct colours")
                } else if let inputs = incoming[point], inputs.count == 1 {
                    precondition(inputs == colors, "Path colour changed before reaching a junction")
                }
            }
            boundary = incoming.reduce(into: [:]) { result, entry in
                if entry.key.line == Double(row.graph.lines.count), entry.value.count == 1 {
                    result[entry.key.column] = entry.value[0]
                }
            }
        }
    }

    private func assertRenderedParents(in rows: [CommitRow], smoothed: Bool) {
        var adjacency: [GitGraphPoint: Set<GitGraphPoint>] = [:]
        var nodes: [GitGraphPoint: GitCommit] = [:]
        var offset = 0.0
        for row in rows {
            let column = row.graph.lines[row.graph.nodeLine].firstIndex { $0.character == "*" }!
            nodes[GitGraphPoint(column: Double(column), line: offset + Double(row.graph.nodeLine) + 0.5)] = row.commit
            let segments = smoothed ? CommitGraphGeometry.drawingSegments(for: row.graph)
                : CommitGraphGeometry.segments(for: row.graph)
            for segment in segments {
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
        // Stable timestamps keep dense graph ordering and hashes reproducible
        // instead of changing which lane layouts are tested on every run.
        process.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_AUTHOR_DATE": "2026-01-01T00:00:00+0000",
            "GIT_COMMITTER_DATE": "2026-01-01T00:00:00+0000"
        ]) { _, fixed in fixed }
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
