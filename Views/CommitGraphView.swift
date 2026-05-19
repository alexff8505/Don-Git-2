import SwiftUI

struct CommitGraphView: View {
    let graph: CommitGraphState
    let isFirstRow: Bool

    private let laneSpacing: CGFloat = 18
    private let nodeRadius: CGFloat = 4.75
    private let lineWidth: CGFloat = 2.5

    var body: some View {
        Canvas { context, size in
            drawVerticalSegments(in: &context, size: size)
            drawParentConnectors(in: &context, size: size)
            drawNode(in: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func drawVerticalSegments(in context: inout GraphicsContext, size: CGSize) {
        let centerY = size.height / 2

        for index in graph.lanesBefore.indices {
            let startY = isFirstRow ? centerY : -lineWidth
            let continuesBelow = graph.lanesAfter.indices.contains(index)
            let endY = continuesBelow ? centerY + lineWidth : centerY
            strokeLine(lane: index, from: startY, to: endY, in: &context)
        }

        for index in graph.lanesAfter.indices {
            let existedAbove = graph.lanesBefore.indices.contains(index)
            let startY = existedAbove ? centerY - lineWidth : centerY
            strokeLine(lane: index, from: startY, to: size.height + lineWidth, in: &context)
        }
    }

    private func drawParentConnectors(in context: inout GraphicsContext, size: CGSize) {
        let start = point(lane: graph.nodeLane, y: size.height / 2)

        for lane in graph.parentLanes where lane != graph.nodeLane {
            var path = Path()
            path.move(to: start)
            path.addCurve(
                to: point(lane: lane, y: size.height + lineWidth),
                control1: CGPoint(x: start.x, y: size.height * 0.72),
                control2: CGPoint(x: point(lane: lane, y: size.height).x, y: size.height * 0.72)
            )
            context.stroke(path, with: .color(ColorPalette.color(for: lane)), style: strokeStyle)
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
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(color), lineWidth: 1.75)
        }
    }

    private func strokeLine(lane: Int, from startY: CGFloat, to endY: CGFloat, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: point(lane: lane, y: startY))
        path.addLine(to: point(lane: lane, y: endY))
        context.stroke(path, with: .color(ColorPalette.color(for: lane)), style: strokeStyle)
    }

    private func point(lane: Int, y: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(lane) * laneSpacing + 10, y: y)
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round)
    }
}

private enum ColorPalette {
    private static let colors: [Color] = [
        .orange,
        .blue,
        .red,
        .cyan,
        .purple,
        .green,
        .indigo,
        .pink
    ]

    static func color(for lane: Int) -> Color {
        colors[abs(lane) % colors.count]
    }
}
