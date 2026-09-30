/// Column coordinates shared by neighbouring ASCII graph lines, including
/// diagonals that Git advances by one character during a lane collapse.
enum CommitGraphGeometry {
    /// Shared by drawing and topology checks, before macOS row sizing.
    static func segments(for graph: CommitGraphState) -> [GitGraphSegment] {
        var result: [GitGraphSegment] = []
        for (lineIndex, line) in graph.lines.enumerated() {
            let previous = lineIndex > 0 ? graph.lines[lineIndex - 1] : graph.previousLine
            let next = lineIndex + 1 < graph.lines.count ? graph.lines[lineIndex + 1] : graph.nextLine
            let top = Double(lineIndex), middle = top + 0.5, bottom = top + 1
            for (column, glyph) in line.enumerated() {
                let x = Double(column)
                let ends = endpoints(column: column, line: line, previous: previous, next: next)
                func add(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, color: [Int]? = nil) {
                    result.append(GitGraphSegment(start: GitGraphPoint(column: x1, line: y1),
                        end: GitGraphPoint(column: x2, line: y2), color: color ?? glyph.color))
                }
                switch glyph.character {
                case "|", "/", "\\":
                    if let upper = ends.upper, let lower = ends.lower { add(upper, top, lower, bottom) }
                case ".":
                    add(x - 1, middle, x, middle)
                    add(x, middle, x, bottom)
                case "-": add(x - 1, middle, x, middle)
                case "_":
                    if let connector = horizontalConnector(in: line), column == connector.first {
                        let target = connector.first - 1
                        let crossing = character(in: next, at: target - 1) == "/"
                        add(Double(target) + (crossing ? 0.5 : 0), bottom,
                            Double(connector.source) - 0.5, bottom)
                    }
                case "*":
                    if let color = graph.incomingColor { add(x, top, x, middle, color: color) }
                    if let color = graph.outgoingColor { add(x, middle, x, bottom, color: color) }
                default: break
                }
            }
            // Octopus merges have intermediate parents below the horizontal bar,
            // as well as the final '.' corner. Every branch needs its own stem.
            for column in next.indices {
                let upper = endpoints(column: column, line: next, previous: line, next: []).upper
                guard let upper, upper.rounded() == upper, line.indices.contains(Int(upper)),
                      line[Int(upper)].character == "-" else { continue }
                result.append(GitGraphSegment(start: GitGraphPoint(column: upper, line: middle),
                    end: GitGraphPoint(column: upper, line: bottom), color: next[column].color))
            }
        }
        return result
    }

    static func endpoints(
        column: Int, line: [GitGraphGlyph], previous: [GitGraphGlyph], next: [GitGraphGlyph]
    ) -> (upper: Double?, lower: Double?) {
        let (upper, lower) = rawEndpoints(column: column, character: line[column].character)
        let glyph = line[column]
        var joinedUpper = upper.map { joinedColumn($0, upperLine: previous, lowerLine: line, fromUpperLine: false) }
        var joinedLower = lower.map { joinedColumn($0, upperLine: line, lowerLine: next, fromUpperLine: true) }

        if glyph.character == "/" {
            if let connector = horizontalConnector(in: previous), column == connector.first - 2 {
                joinedUpper = Double(column) + 1.5
            } else if matches(previous, at: column + 2, character: "\\", color: glyph.color),
                      !matches(previous, at: column, character: "\\", color: glyph.color),
                      !matches(previous, at: column + 1, character: "|", color: glyph.color) {
                // A newly added lane can immediately collapse back to the left.
                joinedUpper = Double(column + 2)
            } else if character(in: previous, at: column + 2) == "/",
                      character(in: line, at: column + 1) == "|" {
                // '| |/' -> '|/|' is a crossing, with separate boundary ports.
                joinedUpper = Double(column) + 1.5
            }
            if horizontalConnector(in: line)?.source == column {
                joinedLower = Double(column) - 0.5
            } else if matches(next, at: column, character: "|", color: glyph.color) {
                // A merge can stop a collapse without changing the lane index.
                joinedLower = Double(column) - 0.5
            } else if character(in: next, at: column - 2) == "/",
                      character(in: next, at: column - 1) == "|" {
                joinedLower = Double(column) - 0.5
            }
        } else if glyph.character == "|" {
            if matches(previous, at: column, character: "/", color: glyph.color) {
                joinedUpper = Double(column) - 0.5
            }
            if matches(next, at: column - 2, character: "|", color: glyph.color),
               !hasIncomingEdge(in: next, at: column, color: glyph.color) {
                // A parent already occupies the lane to the left; Git removes
                // the duplicate instead of emitting another collapse slash.
                joinedLower = Double(column - 2)
            }
        } else if glyph.character == "\\" {
            if matches(next, at: column - 2, character: "/", color: glyph.color),
               !matches(next, at: column, character: "/", color: glyph.color) {
                joinedLower = Double(column)
            } else if matches(next, at: column - 1, character: "|", color: glyph.color),
                      !hasIncomingEdge(in: next, at: column + 1, color: glyph.color) {
                joinedLower = Double(column - 1)
            }
        }
        return (joinedUpper, joinedLower)
    }

    private static func character(in line: [GitGraphGlyph], at index: Int) -> Character? {
        line.indices.contains(index) ? line[index].character : nil
    }

    private static func matches(_ line: [GitGraphGlyph], at index: Int, character: Character, color: [Int]) -> Bool {
        line.indices.contains(index) && line[index].character == character && line[index].color == color
    }

    private static func hasIncomingEdge(in line: [GitGraphGlyph], at column: Int, color: [Int]) -> Bool {
        line.indices.contains { index in
            rawEndpoints(column: index, character: line[index].character).upper == Double(column)
                && (line[index].character == "*" || line[index].color == color)
        }
    }

    /// Underscores cross intermediate vertical lanes. They form one connector;
    /// splitting at every character would create false parent junctions.
    private static func horizontalConnector(in line: [GitGraphGlyph]) -> (first: Int, source: Int)? {
        guard let first = line.firstIndex(where: { $0.character == "_" }),
              let last = line.lastIndex(where: { $0.character == "_" }),
              let source = line.indices.first(where: { $0 > last && line[$0].character == "/" }) else { return nil }
        return (first, source)
    }

    private static func rawEndpoints(column: Int, character: Character) -> (upper: Double?, lower: Double?) {
        switch character {
        case "|", "*": (Double(column), Double(column))
        case "/": (Double(column + 1), Double(column - 1))
        case "\\": (Double(column - 1), Double(column + 1))
        case ".": (nil, Double(column))
        default: (nil, nil)
        }
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

struct GitGraphPoint: Hashable, Sendable {
    let column: Double
    let line: Double
}

struct GitGraphSegment: Hashable, Sendable {
    let start: GitGraphPoint
    let end: GitGraphPoint
    let color: [Int]
}
