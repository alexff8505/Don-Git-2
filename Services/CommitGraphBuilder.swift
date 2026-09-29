import Foundation

/// Preserve Git's lane placement and colour decisions instead of recreating them.
struct CommitGraphBuilder {
    func rows(for commits: [GitCommit], graphOutput: String) throws -> [CommitRow] {
        var blocks: [[[GitGraphGlyph]]] = []
        var pending: [[GitGraphGlyph]] = []
        var hashes: [String] = []

        for line in graphOutput.split(separator: "\n", omittingEmptySubsequences: false) {
            if let marker = line.firstIndex(of: "\u{1f}") {
                let prefix = String(line[..<marker])
                let hash = String(line[line.index(after: marker)...])
                guard hashes.count < commits.count, commits[hashes.count].hash == hash else {
                    throw GitClient.GitClientError.invalidOutput
                }
                hashes.append(hash)
                blocks.append(pending + [glyphs(in: prefix)])
                pending.removeAll(keepingCapacity: true)
            } else {
                let glyphs = glyphs(in: String(line))
                guard glyphs.contains(where: { $0.character != " " }) else { continue }
                // Git's routing rows follow the commit they connect to its parents.
                if blocks.isEmpty {
                    pending.append(glyphs)
                } else {
                    blocks[blocks.count - 1].append(glyphs)
                }
            }
        }

        guard hashes.count == commits.count else { throw GitClient.GitClientError.invalidOutput }
        return commits.enumerated().map { index, commit in
            let lines = blocks[index]
            let nodeColumn = lines[0].firstIndex { $0.character == "*" } ?? 0
            let incoming: [Int]? = index > 0
                ? edgeColor(in: blocks[index - 1].last ?? [], column: nodeColumn, atBottom: true, allowStar: !commits[index - 1].parents.isEmpty) : nil
            let nextLine = lines.count > 1 ? lines[1] : (index + 1 < blocks.count ? blocks[index + 1][0] : [])
            let outgoing = commit.parents.isEmpty ? nil : edgeColor(in: nextLine, column: nodeColumn, atBottom: false)
            return CommitRow(commit: commit, graph: CommitGraphState(
                lines: lines, hasParents: !commit.parents.isEmpty,
                incomingColor: incoming, outgoingColor: outgoing
            ))
        }
    }

    private func edgeColor(in line: [GitGraphGlyph], column: Int, atBottom: Bool, allowStar: Bool = true) -> [Int]? {
        for (index, glyph) in line.enumerated() {
            let endpoint: Int
            switch glyph.character {
            case "|": endpoint = index
            case "*" where allowStar: endpoint = index
            case "/": endpoint = index + (atBottom ? -1 : 1)
            case "\\": endpoint = index + (atBottom ? 1 : -1)
            default: continue
            }
            if endpoint == column { return glyph.color }
        }
        return nil
    }

    private func glyphs(in text: String) -> [GitGraphGlyph] {
        var result: [GitGraphGlyph] = []
        var color: [Int] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\u{1b}" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "[",
                   let end = text[next...].firstIndex(of: "m") {
                    let codes = text[text.index(after: next)..<end].split(separator: ";").compactMap { Int($0) }
                    if codes.isEmpty || codes.contains(0) { color = [] }
                    color.append(contentsOf: codes.filter { $0 != 0 })
                    index = text.index(after: end)
                    continue
                }
            }
            result.append(GitGraphGlyph(character: text[index], color: color))
            index = text.index(after: index)
        }
        return result
    }
}
