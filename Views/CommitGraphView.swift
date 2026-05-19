import SwiftUI

struct CommitGraphView: View {
    let graph: CommitGraphState

    private let laneSpacing: CGFloat = 18
    private let nodeRadius: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            drawVerticalSegments(in: &context, size: size)
            drawParentConnectors(in: &context, size: size)
            drawNode(in: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func drawVerticalSegments(in context: inout GraphicsContext, size: CGSize) {
        for (index, hash) in graph.lanesBefore.enumerated() {
            strokeLine(lane: index, from: 0, to: size.height / 2, hash: hash, in: &context)
        }

        for (index, hash) in graph.lanesAfter.enumerated() {
            strokeLine(lane: index, from: size.height / 2, to: size.height, hash: hash, in: &context)
        }
    }

    private func drawParentConnectors(in context: inout GraphicsContext, size: CGSize) {
        let start = point(lane: graph.nodeLane, y: size.height / 2)

        for lane in graph.parentLanes where lane != graph.nodeLane {
            var path = Path()
            path.move(to: start)
            path.addCurve(
                to: point(lane: lane, y: size.height),
                control1: CGPoint(x: start.x, y: size.height * 0.72),
                control2: CGPoint(x: point(lane: lane, y: size.height).x, y: size.height * 0.72)
            )
            context.stroke(path, with: .color(ColorPalette.color(for: lane)), lineWidth: 2)
        }
    }

    private func drawNode(in context: inout GraphicsContext, size: CGSize) {
        let center = point(lane: graph.nodeLane, y: size.height / 2)
        let rect = CGRect(
            x: center.x - nodeRadius,
            y: center.y - nodeRadius,
            width: nodeRadius * 2,
            height: nodeRadius * 2
        )

        let color = ColorPalette.color(for: graph.nodeLane)
        context.fill(Path(ellipseIn: rect), with: .color(color))

        if graph.isMerge {
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(color), lineWidth: 1.5)
        }
    }

    private func strokeLine(lane: Int, from startY: CGFloat, to endY: CGFloat, hash: String, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: point(lane: lane, y: startY))
        path.addLine(to: point(lane: lane, y: endY))
        context.stroke(path, with: .color(ColorPalette.color(for: hash)), lineWidth: 2)
    }

    private func point(lane: Int, y: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(lane) * laneSpacing + 10, y: y)
    }
}

private enum ColorPalette {
    private static let colors: [Color] = [
        .orange,
        .red,
        .blue,
        .green,
        .purple,
        .pink,
        .teal,
        .indigo
    ]

    static func color(for hash: String) -> Color {
        let scalarTotal = hash.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[abs(scalarTotal) % colors.count]
    }

    static func color(for lane: Int) -> Color {
        colors[abs(lane) % colors.count]
    }
}
