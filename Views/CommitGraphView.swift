import SwiftUI

struct CommitGraphView: View {
    let graph: CommitGraphState
    var isSelected = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let scheme = colorScheme
        let increasedContrast = contrast == .increased
        return Canvas { context, size in
            var colors: [[Int]: Color] = [:]
            func color(for codes: [Int]) -> Color {
                if let cached = colors[codes] { return cached }
                let value = GitGraphColorPalette.color(for: codes, scheme: scheme,
                                                       increasedContrast: increasedContrast)
                colors[codes] = value
                return value
            }
            let inset: CGFloat = 7
            let center = size.height / 2
            let unit = (size.height - inset - center) / (CGFloat(max(1, graph.lines.count)) - 0.5)
            func point(_ value: GitGraphPoint) -> CGPoint {
                let y = value.line <= 0.5
                    ? inset + CGFloat(value.line) * 2 * (center - inset)
                    : center + (CGFloat(value.line) - 0.5) * unit
                return CGPoint(x: CGFloat(value.column) * 8 + 10, y: y)
            }
            let stroke = StrokeStyle(lineWidth: increasedContrast ? 2.4 : 1.8,
                                     lineCap: .round, lineJoin: .round)
            let casing = StrokeStyle(lineWidth: stroke.lineWidth + 2, lineCap: .round, lineJoin: .round)
            let background = Color(nsColor: .controlBackgroundColor)
            let outgoingPorts = Set(graph.nextLine.indices.compactMap {
                CommitGraphGeometry.endpoints(column: $0, line: graph.nextLine, previous: graph.lines.last ?? [], next: []).upper
            })
            var paths: [(path: Path, start: CGPoint, end: CGPoint, color: [Int])] = []
            for segment in CommitGraphGeometry.segments(for: graph) {
                let start = point(segment.start), end = point(segment.end)
                var path = Path()
                // Boundary extensions stay vertical and share exact coordinates
                // with adjacent cells, including the native table's row spacing.
                if segment.start.line == 0 {
                    path.move(to: CGPoint(x: start.x, y: 0))
                    path.addLine(to: start)
                } else if segment.start.line == Double(graph.lines.count), outgoingPorts.contains(segment.start.column) {
                    path.move(to: CGPoint(x: start.x, y: size.height))
                    path.addLine(to: start)
                } else {
                    path.move(to: start)
                }
                if start.x != end.x, start.y != end.y {
                    let bend = (end.y - start.y) * 0.45
                    path.addCurve(to: end,
                        control1: CGPoint(x: start.x, y: start.y + bend),
                        control2: CGPoint(x: end.x, y: end.y - bend))
                } else {
                    path.addLine(to: end)
                }
                if segment.end.line == Double(graph.lines.count), outgoingPorts.contains(segment.end.column) {
                    path.addLine(to: CGPoint(x: end.x, y: size.height))
                }
                paths.append((path, start, end, segment.color))
            }
            // Lay selected-row casings underneath every coloured stroke. Drawing
            // them one segment at a time would erase the adjoining branch ends.
            if isSelected {
                for item in paths { context.stroke(item.path, with: .color(background), style: casing) }
            }
            for item in paths { context.stroke(item.path, with: .color(color(for: item.color)), style: stroke) }
            for item in paths where item.start.x != item.end.x {
                if paths.contains(where: { crosses(item.start, item.end, $0.start, $0.end) }) {
                    // Keep junction endpoints solid; clear only the interior of
                    // a path that crosses another lane without connecting to it.
                    let interior = item.path.trimmedPath(from: 0.08, to: 0.92)
                    context.stroke(interior, with: .color(background), style: casing)
                    context.stroke(interior, with: .color(color(for: item.color)), style: stroke)
                }
            }
            if let column = graph.lines[graph.nodeLine].firstIndex(where: { $0.character == "*" }) {
                let position = point(GitGraphPoint(column: Double(column), line: Double(graph.nodeLine) + 0.5))
                let radius: CGFloat = graph.parentCount > 1 ? 4 : 3.3
                let node = Path(ellipseIn: CGRect(x: position.x - radius, y: position.y - radius,
                                                width: radius * 2, height: radius * 2))
                let nodeColor = color(for: graph.nodeColor)
                if isSelected {
                    let halo = Path(ellipseIn: CGRect(x: position.x - radius - 1.5, y: position.y - radius - 1.5,
                                                     width: radius * 2 + 3, height: radius * 2 + 3))
                    context.fill(halo, with: .color(background))
                }
                context.fill(node, with: .color(graph.parentCount > 1 ? Color(nsColor: .controlBackgroundColor) : nodeColor))
                context.stroke(node, with: .color(nodeColor), lineWidth: graph.parentCount > 1 ? 2 : 1)
            }
            if CGFloat(graph.laneCount) * 16 + 4 > size.width {
                let marker = CGRect(x: size.width - 16, y: center - 8, width: 16, height: 16)
                context.fill(Path(roundedRect: marker, cornerRadius: 3), with: .color(Color(nsColor: .controlBackgroundColor)))
                context.draw(Text("…").font(.caption).foregroundStyle(.secondary), at: CGPoint(x: marker.midX, y: marker.midY))
            }
        }
        .clipped()
        .help("\(accessibilityDescription). Drag the Graph column divider to see more lanes.")
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let kind = graph.parentCount == 0 ? "Root commit" : graph.parentCount > 1 ? "Merge commit, \(graph.parentCount) parents" : "Commit, 1 parent"
        let column = graph.lines[graph.nodeLine].firstIndex { $0.character == "*" } ?? 0
        return "\(kind), lane \(column / 2 + 1) of \(graph.laneCount)"
    }
}

/// Crossings lie inside both segments; a shared endpoint is a junction.
private func crosses(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
    let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
    let cd = CGPoint(x: d.x - c.x, y: d.y - c.y)
    let denominator = ab.x * cd.y - ab.y * cd.x
    guard abs(denominator) > 0.001 else { return false }
    let ac = CGPoint(x: c.x - a.x, y: c.y - a.y)
    let t = (ac.x * cd.y - ac.y * cd.x) / denominator
    let u = (ac.x * ab.y - ac.y * ab.x) / denominator
    return t > 0.001 && t < 0.999 && u > 0.001 && u < 0.999
}
