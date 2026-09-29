import SwiftUI

struct CommitGraphView: View {
    let graph: CommitGraphState

    var body: some View {
        Canvas { context, size in
            // Keep all diagonals inside the cell. Only vertical endpoints bleed into
            // the native table's inter-row spacing, so clipping cannot truncate joins.
            let inset: CGFloat = 7
            let contentBottom = size.height - inset
            let center = size.height / 2
            let unit = (contentBottom - center) / (CGFloat(max(1, graph.lines.count)) - 0.5)
            for (lineIndex, line) in graph.lines.enumerated() {
                let top = lineIndex == 0 ? inset : size.height / 2 + (CGFloat(lineIndex) - 0.5) * unit
                let bottom = size.height / 2 + (CGFloat(lineIndex) + 0.5) * unit
                for (column, glyph) in line.enumerated() {
                    let x = CGFloat(column) * 7 + 8
                    let middle = lineIndex == 0 ? size.height / 2 : (top + bottom) / 2
                    var path = Path()
                    switch glyph.character {
                    case "|":
                        path.move(to: CGPoint(x: x, y: top))
                        path.addLine(to: CGPoint(x: x, y: bottom))
                    case "/":
                        path.move(to: CGPoint(x: x + 7, y: top))
                        path.addLine(to: CGPoint(x: x - 7, y: bottom))
                    case "\\":
                        path.move(to: CGPoint(x: x - 7, y: top))
                        path.addLine(to: CGPoint(x: x + 7, y: bottom))
                    case ".":
                        path.move(to: CGPoint(x: x - 7, y: middle))
                        path.addLine(to: CGPoint(x: x, y: middle))
                        path.addLine(to: CGPoint(x: x, y: bottom))
                    case "_", "-":
                        let y = glyph.character == "_" ? bottom : middle
                        path.move(to: CGPoint(x: x - 7, y: y))
                        path.addLine(to: CGPoint(x: x + 7, y: y))
                    case "*":
                        // Git's star is neutral; the coloured edges carry lane identity.
                        if let color = graph.incomingColor {
                            var incoming = Path()
                            incoming.move(to: CGPoint(x: x, y: 0))
                            incoming.addLine(to: CGPoint(x: x, y: middle))
                            context.stroke(incoming, with: .color(GitGraphColorPalette.color(for: color)), lineWidth: 1.5)
                        }
                        if let color = graph.outgoingColor {
                            var outgoing = Path()
                            outgoing.move(to: CGPoint(x: x, y: middle))
                            outgoing.addLine(to: CGPoint(x: x, y: lineIndex == graph.lines.count - 1 ? size.height : bottom))
                            context.stroke(outgoing, with: .color(GitGraphColorPalette.color(for: color)), lineWidth: 1.5)
                        }
                        let node = Path(ellipseIn: CGRect(x: x - 3, y: middle - 3, width: 6, height: 6))
                        context.fill(node, with: .color(.primary))
                    default:
                        continue
                    }
                    // Extend each boundary endpoint vertically, rather than extending
                    // diagonals beyond the row and relying on unclipped drawing.
                    var bridges = Path()
                    let upperX: CGFloat?
                    let lowerX: CGFloat?
                    switch glyph.character {
                    case "|": upperX = x; lowerX = x
                    case "/": upperX = x + 7; lowerX = x - 7
                    case "\\": upperX = x - 7; lowerX = x + 7
                    case ".": upperX = nil; lowerX = x
                    default: upperX = nil; lowerX = nil
                    }
                    if lineIndex == 0, let upperX {
                        bridges.move(to: CGPoint(x: upperX, y: 0))
                        bridges.addLine(to: CGPoint(x: upperX, y: inset))
                    }
                    if lineIndex == graph.lines.count - 1, let lowerX {
                        bridges.move(to: CGPoint(x: lowerX, y: contentBottom))
                        bridges.addLine(to: CGPoint(x: lowerX, y: size.height))
                    }
                    context.stroke(bridges, with: .color(GitGraphColorPalette.color(for: glyph.color)), lineWidth: 1.5)
                    context.stroke(path, with: .color(GitGraphColorPalette.color(for: glyph.color)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .butt, lineJoin: .miter))
                }
            }
        }
        .accessibilityLabel(graph.hasParents ? "Commit with parent connections" : "Root commit")
    }
}
