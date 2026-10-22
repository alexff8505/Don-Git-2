import Foundation

/// Colour the connected paths, independently of Git's transient ANSI colours.
/// Geometry still comes from the original glyphs, whose colours also help Git's
/// expansion/collapse rules distinguish crossings from real junctions.
enum CommitGraphColors {
    static func apply(to rows: [CommitRow]) -> [CommitRow] {
        var boundary: [Double: [Int]] = [:]
        return rows.map { row in
            let segments = CommitGraphGeometry.segments(for: row.graph)
            let directed = segments.map { segment in
                // Underscore connectors run back to the left; octopus bars
                // run right from the commit, halfway through a text line.
                if segment.start.line == segment.end.line, segment.start.line.rounded() == segment.start.line {
                    return GitGraphSegment(start: segment.end, end: segment.start, color: segment.color)
                }
                return segment
            }
            let incoming = Dictionary(grouping: directed.indices, by: { directed[$0].end })
            let outgoing = Dictionary(grouping: directed.indices, by: { directed[$0].start })
            let node = GitGraphPoint(column: Double(row.graph.lines[row.graph.nodeLine]
                .firstIndex { $0.character == "*" } ?? 0), line: Double(row.graph.nodeLine) + 0.5)
            let points = Set(directed.flatMap { [$0.start, $0.end] } + [node])
            var pendingCount = incoming.mapValues(\.count)
            var pending = points.filter { incoming[$0] == nil }.sorted {
                $0.line == $1.line ? $0.column < $1.column : $0.line < $1.line
            }
            var used = Set(boundary.values)
            var colors: [Int: [Int]] = [:]
            var pointColors: [GitGraphPoint: [Int]] = [:]

            func freshColor(preferred: [Int]) -> [Int] {
                let palette = [[31], [32], [34], [35], [36], [33],
                    [1, 31], [1, 32], [1, 34], [1, 33], [1, 36], [1, 35]]
                let color = ([preferred].filter { !$0.isEmpty } + palette
                    + (16...231).map { [38, 5, $0] }).first { !used.contains($0) } ?? [34]
                used.insert(color)
                return color
            }

            // Prefer the straight continuation at a split or join. The other
            // incoming paths keep their own colour right up to that junction.
            func byStraightness(_ first: Int, _ second: Int) -> Bool {
                let a = abs(directed[first].end.column - directed[first].start.column)
                let b = abs(directed[second].end.column - directed[second].start.column)
                return a == b ? first < second : a < b
            }
            var cursor = 0
            while cursor < pending.count {
                let point = pending[cursor]
                cursor += 1
                let inputs = (incoming[point] ?? []).sorted(by: byStraightness)
                let outputs = (outgoing[point] ?? []).sorted(by: byStraightness)
                let inherited = inputs.first.flatMap { colors[$0] }
                    ?? (point.line == 0 ? boundary[point.column] : nil)
                let preferred = point == node ? row.graph.nodeColor
                    : outputs.first.map { segments[$0].color } ?? [34]
                let color = inherited ?? freshColor(preferred: preferred)
                pointColors[point] = color
                for (offset, index) in outputs.enumerated() {
                    colors[index] = offset == 0 ? color : freshColor(preferred: segments[index].color)
                    let end = directed[index].end
                    pendingCount[end, default: 0] -= 1
                    if pendingCount[end] == 0 { pending.append(end) }
                }
            }
            boundary = Dictionary(uniqueKeysWithValues: pointColors.compactMap { point, color in
                point.line == Double(row.graph.lines.count) ? (point.column, color) : nil
            })
            var graph = row.graph
            graph.pathSegments = segments.enumerated().map { index, segment in
                GitGraphSegment(start: segment.start, end: segment.end, color: colors[index] ?? segment.color)
            }
            graph.displayNodeColor = pointColors[node]
            return CommitRow(commit: row.commit, graph: graph)
        }
    }
}
