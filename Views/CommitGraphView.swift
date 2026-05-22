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
        let connectorTargetY = size.height - nodeRadius

        for index in graph.lanesBefore.indices {
            if index == graph.nodeLane {
                guard graph.hasIncomingLane else { continue }
                let startY = isFirstRow ? centerY - nodeRadius : 0
                strokeLine(lane: index, from: startY, to: centerY - nodeRadius, in: &context)
                continue
            }

            if let afterHash = graph.lanesAfter[safe: index],
               afterHash == graph.lanesBefore[index] {
                strokeLine(lane: index, from: 0, to: size.height, in: &context)
            } else {
                strokeLine(lane: index, from: 0, to: centerY, in: &context)
            }
        }

        for index in graph.lanesAfter.indices {
            if index == graph.nodeLane {
                strokeLine(lane: index, from: centerY + nodeRadius, to: size.height, in: &context)
                continue
            }

            guard graph.lanesBefore[safe: index] != graph.lanesAfter[index] else { continue }
            let startY = graph.parentLanes.contains(index) ? connectorTargetY : centerY
            strokeLine(lane: index, from: startY, to: size.height, in: &context)
        }
    }

    private func drawParentConnectors(in context: inout GraphicsContext, size: CGSize) {
        let start = point(lane: graph.nodeLane, y: size.height / 2)

        for lane in graph.parentLanes where lane != graph.nodeLane {
            let targetY = size.height - nodeRadius
            var path = Path()
            path.move(to: point(lane: graph.nodeLane, y: size.height / 2 + nodeRadius))
            path.addCurve(
                to: point(lane: lane, y: targetY),
                control1: CGPoint(x: start.x, y: size.height * 0.72),
                control2: CGPoint(x: point(lane: lane, y: targetY).x, y: size.height * 0.72)
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
