import SwiftUI

struct CommitGraphView: View {
    let graph: CommitGraphState
    var isSelected = false
    var workingTreeConnection: WorkingTreeGraphConnection?
    var graphInset: CGFloat = 0
    var nodeCenter: CGFloat?
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
            let center = nodeCenter ?? size.height / 2
            let nodeLine = CGFloat(graph.nodeLine) + 0.5
            let unit = (size.height - center) / (CGFloat(graph.lines.count) - nodeLine)
            func point(_ value: GitGraphPoint) -> CGPoint {
                let y = CGFloat(value.line) <= nodeLine
                    ? CGFloat(value.line) / nodeLine * center
                    : center + (CGFloat(value.line) - nodeLine) * unit
                return CGPoint(x: CGFloat(value.column) * 8 + 10 + graphInset, y: y)
            }
            let stroke = StrokeStyle(lineWidth: increasedContrast ? 2.4 : 1.8,
                                     lineCap: .round, lineJoin: .round)
            let casing = StrokeStyle(lineWidth: stroke.lineWidth + 2, lineCap: .round, lineJoin: .round)
            let background = Color(nsColor: .controlBackgroundColor)
            let segments = CommitGraphGeometry.segments(for: graph)
            var paths: [(path: Path, start: CGPoint, end: CGPoint, color: [Int])] = []
            for segment in segments {
                let start = point(segment.start), end = point(segment.end)
                var path = Path()
                path.move(to: start)
                if start.x != end.x, start.y != end.y {
                    let bend = (end.y - start.y) * 0.45
                    path.addCurve(to: end,
                        control1: CGPoint(x: start.x, y: start.y + bend),
                        control2: CGPoint(x: end.x, y: end.y - bend))
                } else {
                    path.addLine(to: end)
                }
                paths.append((path, start, end, segment.color))
            }
            // Lay selected-row casings underneath every coloured stroke. Drawing
            // them one segment at a time would erase the adjoining branch ends.
            if isSelected {
                for item in paths { context.stroke(item.path, with: .color(background), style: casing) }
            }
            for item in paths { context.stroke(item.path, with: .color(color(for: item.color)), style: stroke) }
            for index in paths.indices where paths[index].start.x != paths[index].end.x {
                let item = paths[index]
                if paths.contains(where: { crosses(item.start, item.end, $0.start, $0.end) }) {
                    // Separate the crossing from the lane beneath, then restore
                    // the entire connected route. The casing's round ends can
                    // otherwise erase an adjoining curve even after trimming.
                    let interior = item.path.trimmedPath(from: 0.08, to: 0.92)
                    context.stroke(interior, with: .color(background), style: casing)
                    for connected in CommitGraphGeometry.connectedStrokeIndices(to: index, in: segments) {
                        let route = paths[connected]
                        context.stroke(route.path, with: .color(color(for: route.color)), style: stroke)
                    }
                }
            }
            if workingTreeConnection == .continuation {
                var stem = Path()
                stem.move(to: CGPoint(x: 10, y: 0))
                stem.addLine(to: CGPoint(x: 10, y: size.height))
                context.stroke(stem, with: .color(.secondary),
                               style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
            if let column = graph.lines[graph.nodeLine].firstIndex(where: { $0.character == "*" }) {
                let position = point(GitGraphPoint(column: Double(column), line: Double(graph.nodeLine) + 0.5))
                let radius: CGFloat = graph.parentCount > 1 ? 4 : 3.3
                let node = Path(ellipseIn: CGRect(x: position.x - radius, y: position.y - radius,
                                                width: radius * 2, height: radius * 2))
                let nodeColor = color(for: graph.nodeColor)
                if workingTreeConnection == .head {
                    var workingTreeStem = Path()
                    workingTreeStem.move(to: CGPoint(x: 10, y: 0))
                    workingTreeStem.addCurve(to: position,
                        control1: CGPoint(x: 10, y: position.y * 0.6),
                        control2: CGPoint(x: position.x, y: position.y * 0.4))
                    context.stroke(workingTreeStem, with: .color(.secondary),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                if isSelected {
                    let halo = Path(ellipseIn: CGRect(x: position.x - radius - 1.5, y: position.y - radius - 1.5,
                                                     width: radius * 2 + 3, height: radius * 2 + 3))
                    context.fill(halo, with: .color(background))
                }
                context.fill(node, with: .color(graph.parentCount > 1 ? Color(nsColor: .controlBackgroundColor) : nodeColor))
                context.stroke(node, with: .color(nodeColor), lineWidth: graph.parentCount > 1 ? 2 : 1)
            }
            if CGFloat(graph.laneCount) * 16 + graphInset + 4 > size.width {
                let marker = CGRect(x: size.width - 16, y: center - 8, width: 16, height: 16)
                context.fill(Path(roundedRect: marker, cornerRadius: 3), with: .color(Color(nsColor: .controlBackgroundColor)))
                context.draw(Text("…").font(.caption).foregroundStyle(.secondary), at: CGPoint(x: marker.midX, y: marker.midY))
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct WorkingTreeGraphView: View {
    let connectsToHEAD: Bool
    let nodeCenter: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: 10, y: nodeCenter)
            if connectsToHEAD {
                var stem = Path()
                stem.move(to: CGPoint(x: center.x, y: center.y + 5))
                stem.addLine(to: CGPoint(x: center.x, y: size.height))
                context.stroke(stem, with: .color(.secondary), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
            context.stroke(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)),
                           with: .color(.secondary), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
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
