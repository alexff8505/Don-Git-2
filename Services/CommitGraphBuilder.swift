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
                let hash = String(line[line.index(after: marker)...].split(separator: "\u{1f}", omittingEmptySubsequences: false)[0])
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
        var rows: [CommitRow] = []
        for (index, commit) in commits.enumerated() {
            let lines = blocks[index]
            let nodeColumn = lines[0].firstIndex { $0.character == "*" } ?? 0
            let previous = index > 0 ? blocks[index - 1].last ?? [] : []
            let incoming = edgeColor(in: previous, column: nodeColumn, atBottom: true,
                starColor: index > 0 ? rows[index - 1].graph.outgoingColor : nil)
            let nextLine = lines.count > 1 ? lines[1] : (index + 1 < blocks.count ? blocks[index + 1][0] : [])
            let outgoing = commit.parents.isEmpty ? nil : edgeColor(in: nextLine, column: nodeColumn, atBottom: false,
                starColor: incoming ?? followingColor(blocks: blocks, after: index, column: nodeColumn) ?? [34])
            rows.append(CommitRow(commit: commit, graph: CommitGraphState(
                lines: lines,
                previousLine: previous,
                nextLine: index + 1 < blocks.count ? blocks[index + 1][0] : [],
                parentCount: commit.parents.count,
                incomingColor: incoming, outgoingColor: outgoing
            )))
        }
        return rows
    }

    private func followingColor(blocks: [[[GitGraphGlyph]]], after index: Int, column: Int) -> [Int]? {
        // A neutral '*' inherits the lane colour. Look beyond a run of stars
        // only when there is no incoming lane yet (for example, a new tip).
        for block in blocks[index...] {
            for line in block {
                if let color = edgeColor(in: line, column: column, atBottom: false, starColor: nil) {
                    return color
                }
                guard line.indices.contains(column), line[column].character == "*" else { return nil }
            }
        }
        return nil
    }

    private func edgeColor(in line: [GitGraphGlyph], column: Int, atBottom: Bool, starColor: [Int]?) -> [Int]? {
        for (index, glyph) in line.enumerated() {
            let endpoint: Int
            switch glyph.character {
            case "|": endpoint = index
            case "*":
                if index == column { return starColor }
                continue
            case "/": endpoint = index + (atBottom ? -1 : 1)
            case "\\": endpoint = index + (atBottom ? 1 : -1)
            case "." where atBottom: endpoint = index
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
