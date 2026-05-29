import SwiftUI

struct CommitGraphView: View {
    let graph: CommitGraphState
    let isFirstRow: Bool

    private let laneSpacing: CGFloat = 14
    private let nodeRadius: CGFloat = 4.2
    private let lineWidth: CGFloat = 2.25
    private let connectorLandingRatio: CGFloat = 0.78
    private let nodeFill = Color(red: 0.07, green: 0.12, blue: 0.17)

    var body: some View {
        Canvas { context, size in
            drawVerticalSegments(in: &context, size: size)
            drawLaneMoves(in: &context, size: size)
            drawParentConnectors(in: &context, size: size)
            drawNode(in: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private func drawVerticalSegments(in context: inout GraphicsContext, size: CGSize) {
        let centerY = size.height / 2
        let connectorTargetY = connectorLandingY(in: size)
        let movingFromLanes = Set(graph.laneMoves.map(\.fromLane))
        let movingToLanes = Set(graph.laneMoves.map(\.toLane))

        for index in graph.lanesBefore.indices {
            if index == graph.nodeLane {
                guard graph.hasIncomingLane else { continue }
                let startY = isFirstRow ? centerY - nodeRadius : 0
                strokeLine(lane: index, from: startY, to: centerY - nodeRadius, in: &context)
                continue
            }

            if let afterHash = graph.lanesAfter[safe: index],
               afterHash == graph.lanesBefore[index],
               !movingFromLanes.contains(index) {
                strokeLine(lane: index, from: 0, to: size.height, in: &context)
            } else {
                strokeLine(lane: index, from: 0, to: centerY, in: &context)
            }
        }

        for index in graph.lanesAfter.indices {
            if index == graph.nodeLane {
                guard graph.parentLanes.contains(index) else { continue }
                strokeLine(lane: index, from: centerY + nodeRadius, to: size.height, in: &context)
                continue
            }

            guard movingToLanes.contains(index) || graph.lanesBefore[safe: index] != graph.lanesAfter[index] else { continue }
            let startY = graph.parentLanes.contains(index) || movingToLanes.contains(index) ? connectorTargetY : centerY
            strokeLine(lane: index, from: startY, to: size.height, in: &context)
        }
    }

    private func drawLaneMoves(in context: inout GraphicsContext, size: CGSize) {
        let centerY = size.height / 2
        let targetY = connectorLandingY(in: size)

        for move in graph.laneMoves {
            var path = Path()
            path.move(to: point(lane: move.fromLane, y: centerY))
            path.addCurve(
                to: point(lane: move.toLane, y: targetY),
                control1: point(lane: move.fromLane, y: targetY),
                control2: point(lane: move.toLane, y: centerY)
            )
            context.stroke(path, with: .color(GitGraphColorPalette.color(for: move.toLane)), style: connectorStrokeStyle)
        }
    }

    private func drawParentConnectors(in context: inout GraphicsContext, size: CGSize) {
        let centerY = size.height / 2

        for lane in graph.parentLanes where lane != graph.nodeLane {
            let direction = lane > graph.nodeLane ? CGFloat(1) : CGFloat(-1)
            let start = point(lane: graph.nodeLane, y: centerY)
            let origin = CGPoint(x: start.x + nodeRadius * direction, y: start.y)
            let target = point(lane: lane, y: connectorLandingY(in: size))
            let controlY = centerY + (target.y - centerY) * 0.68

            var path = Path()
            path.move(to: origin)
            path.addCurve(
                to: target,
                control1: CGPoint(x: origin.x, y: controlY),
                control2: CGPoint(x: target.x, y: controlY)
            )
            context.stroke(path, with: .color(GitGraphColorPalette.color(for: lane)), style: connectorStrokeStyle)

            strokeLine(lane: lane, from: target.y - lineWidth, to: target.y + lineWidth, in: &context)
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

        let node = Path(ellipseIn: rect)
        context.fill(node, with: .color(nodeFill))
        context.stroke(node, with: .color(.white), lineWidth: 3)
    }

    private func strokeLine(lane: Int, from startY: CGFloat, to endY: CGFloat, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: point(lane: lane, y: startY))
        path.addLine(to: point(lane: lane, y: endY))
        context.stroke(path, with: .color(GitGraphColorPalette.color(for: lane)), style: strokeStyle)
    }

    private func point(lane: Int, y: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(lane) * laneSpacing + 8, y: y)
    }

    private func connectorLandingY(in size: CGSize) -> CGFloat {
        min(size.height - nodeRadius, size.height * connectorLandingRatio)
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round)
    }

    private var connectorStrokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
