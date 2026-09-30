/// Column coordinates shared by neighbouring ASCII graph lines, including
/// diagonals that Git advances by one character during a lane collapse.
enum CommitGraphGeometry {
    static func endpoints(
        column: Int, line: [GitGraphGlyph], previous: [GitGraphGlyph], next: [GitGraphGlyph]
    ) -> (upper: Double?, lower: Double?) {
        let upper: Double?
        let lower: Double?
        switch line[column].character {
        case "|", "*": upper = Double(column); lower = Double(column)
        case "/": upper = Double(column + 1); lower = Double(column - 1)
        case "\\": upper = Double(column - 1); lower = Double(column + 1)
        case ".": upper = nil; lower = Double(column)
        default: upper = nil; lower = nil
        }
        return (
            upper.map { joinedColumn($0, upperLine: previous, lowerLine: line, fromUpperLine: false) },
            lower.map { joinedColumn($0, upperLine: line, lowerLine: next, fromUpperLine: true) }
        )
    }

    private static func joinedColumn(
        _ column: Double, upperLine: [GitGraphGlyph], lowerLine: [GitGraphGlyph], fromUpperLine: Bool
    ) -> Double {
        for (index, glyph) in upperLine.enumerated() {
            let direction: Int
            switch glyph.character {
            case "/": direction = -1
            case "\\": direction = 1
            default: continue
            }
            let nextIndex = index + direction
            guard lowerLine.indices.contains(nextIndex),
                  lowerLine[nextIndex].character == glyph.character else { continue }
            // A continuing diagonal spans one character rather than two. Any
            // vertical lane merging here must meet it at the same shared point.
            let originalColumn = Double(fromUpperLine ? nextIndex : index)
            if column == originalColumn {
                return Double(index) + Double(direction) / 2
            }
        }
        return column
    }
}
