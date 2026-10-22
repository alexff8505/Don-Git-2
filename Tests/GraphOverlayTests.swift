import AppKit
import SwiftUI

@main
struct GraphOverlayTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        testCrossingCurveHasNoBreak()
        testMergeRoutesDoNotBulge()
        testMergePathColorsRenderDistinctly()
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 800, height: 3_000))
        let source = OverlayTestRows()
        table.dataSource = source
        table.rowHeight = 42
        table.intercellSpacing = NSSize(width: 3, height: 7)
        for name in ["Graph", "Commit", "Hash", "Author", "Date"] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            column.width = 120
            table.addTableColumn(column)
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 240))
        scroll.documentView = table
        table.reloadData()
        let attachment = CommitGraphAttachmentView()
        let rows = (0..<60).map { index in
            CommitRow(commit: GitCommit(hash: "\(index)", parents: [], authorName: "Test", authorEmail: "",
                authoredAt: .distantPast, subject: "Test", refs: []),
                graph: CommitGraphState(lines: [[GitGraphGlyph(character: "*", color: [31])]],
                    previousLine: [], nextLine: [], parentCount: 0, incomingColor: nil, outgoingColor: nil))
        }
        attachment.update(rows: rows, hasLocalChanges: false)
        attachment.connect(to: table, clip: scroll.contentView)
        let overlay = scroll.contentView.subviews.last!
        precondition(overlay !== table && overlay.superview === table.superview,
                     "The graph must sit above the document, outside native row clipping")
        precondition(overlay.hitTest(NSPoint(x: 10, y: 10)) == nil,
                     "Graph drawing must not intercept native table clicks or scrolling")
        precondition(!overlay.isOpaque, "Native selection and alternating rows must remain visible")
        precondition(overlay.frame.width == table.rect(ofColumn: 0).width)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        precondition(overlay.frame.minY == scroll.contentView.bounds.minY,
                     "Scroll notifications must keep the graph aligned with the visible rows")
        table.tableColumns[0].width = 220
        precondition(overlay.frame.width == table.rect(ofColumn: 0).width,
                     "Direct SwiftUI column resizing must update the clip even without a native notification")
        table.selectRowIndexes(IndexSet(integer: 12), byExtendingSelection: false)
        precondition(table.selectedRow == 12)
        attachment.disconnect()
        precondition(overlay.superview == nil, "Repository/table replacement must remove the old graph")
        print("Passed graph overlay checks, including pixel continuity at the WTC crossing, row clipping, native input, scrolling, column resizing and cleanup.")
    }

    @MainActor private static func testCrossingCurveHasNoBreak() {
        func line(_ text: String) -> [GitGraphGlyph] {
            text.enumerated().map { index, character in
                GitGraphGlyph(character: character, color: index == 2 ? [32] : [31])
            }
        }
        // The WTC branch at b50112d: two collapse slashes meet immediately
        // beside a green lane. Its crossing outline must not erase that join.
        let graph = CommitGraphState(lines: [line("| | *"), line("| |/"), line("|/|")],
            previousLine: line("| *"), nextLine: line("* |"), parentCount: 1,
            incomingColor: nil, outgoingColor: [31])
        for selected in [false, true] {
            let renderer = ImageRenderer(content: CommitGraphView(graph: graph, isSelected: selected)
                .frame(width: 80, height: 72).background(Color.gray)
                .environment(\.colorScheme, .dark))
            renderer.scale = 4
            guard let image = renderer.cgImage else { preconditionFailure("Could not render crossing fixture") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            let segments = CommitGraphGeometry.drawingSegments(for: graph)
            for segment in segments where segment.start.column != segment.end.column && segment.color == [31] {
                func point(_ point: GitGraphPoint) -> CGPoint {
                    CGPoint(x: point.column * 8 + 10,
                            y: point.line <= 0.5 ? point.line * 72 : 36 + (point.line - 0.5) * 14.4)
                }
                let start = point(segment.start), end = point(segment.end)
                let bend = (end.y - start.y) * 0.45
                for step in 0...100 {
                    let t = CGFloat(step) / 100, u = 1 - t
                    let x = u*u*u*start.x + 3*u*u*t*start.x + 3*u*t*t*end.x + t*t*t*end.x
                    let y = u*u*u*start.y + 3*u*u*t*(start.y + bend)
                        + 3*u*t*t*(end.y - bend) + t*t*t*end.y
                    // Smoothing can start at the commit itself; its node and
                    // selection halo intentionally cover the first few pixels.
                    if hypot(x - 42, y - 36) < 5 { continue }
                    // Sample the centre of the actual curved stroke at 4x scale.
                    let color = bitmap.colorAt(x: min(bitmap.pixelsWide - 1, Int(x * 4)),
                                               y: min(bitmap.pixelsHigh - 1, Int(y * 4)))!.usingColorSpace(.sRGB)!
                    precondition(color.redComponent > color.greenComponent * 1.5,
                                 "Crossing outline erased the red curve at \(x), \(y), selected: \(selected)")
                }
            }
        }
    }

    @MainActor private static func testMergeRoutesDoNotBulge() {
        func line(_ text: String) -> [GitGraphGlyph] {
            text.map { GitGraphGlyph(character: $0, color: [34]) }
        }
        // avail-admin d105896: Git temporarily expands both passing lanes,
        // then collapses them again over four routing lines below the merge.
        let graph = CommitGraphState(lines: [line("* | |"), line("|\\ \\ \\"),
            line("| |/ /"), line("|/| /"), line("| |/")],
            previousLine: line("| * |"), nextLine: line("| *"), parentCount: 2,
            incomingColor: [31], outgoingColor: [34])
        let segments = CommitGraphGeometry.drawingSegments(for: graph)
        precondition(segments.allSatisfy { max($0.start.column, $0.end.column) <= 4 },
                     "Temporary ASCII lane expansion must not become a sideways bulge")
        let crossing = segments.firstIndex { $0.start == GitGraphPoint(column: 2, line: 0.5)
            && $0.end == GitGraphPoint(column: 0, line: 4) }!
        let branch = segments.firstIndex { $0.start == GitGraphPoint(column: 0, line: 1)
            && $0.end == GitGraphPoint(column: 2, line: 5) }!
        precondition(!CommitGraphGeometry.connectedStrokeIndices(to: crossing, in: segments).contains(branch),
                     "A same-colour branch must not erase the separation at its crossing")
        for selected in [false, true] {
            let renderer = ImageRenderer(content: CommitGraphView(graph: graph, isSelected: selected)
                .frame(width: 80, height: 96).background(Color.gray)
                .environment(\.colorScheme, .dark))
            renderer.scale = 4
            let bitmap = NSBitmapImageRep(cgImage: renderer.cgImage!)
            for x in 45..<bitmap.pixelsWide / 4 {
                for y in 0..<bitmap.pixelsHigh / 4 {
                    let color = bitmap.colorAt(x: x * 4, y: y * 4)!.usingColorSpace(.sRGB)!
                    precondition(color.blueComponent <= color.redComponent * 1.5,
                                 "Merge rendering contains a blue bulge outside the occupied lanes")
                }
            }
        }
    }

    @MainActor private static func testMergePathColorsRenderDistinctly() {
        func line(_ text: String) -> [GitGraphGlyph] {
            text.map { GitGraphGlyph(character: $0, color: [34]) }
        }
        let before = CommitGraphState(lines: [line("| * |")], previousLine: [], nextLine: line("* | |"),
            parentCount: 1, incomingColor: [34], outgoingColor: [34])
        let merge = CommitGraphState(lines: [line("* | |"), line("|\\ \\ \\"),
            line("| |/ /"), line("|/| /"), line("| |/")],
            previousLine: line("| * |"), nextLine: line("| *"), parentCount: 2,
            incomingColor: [34], outgoingColor: [34])
        let rows = [before, merge].enumerated().map { index, graph in
            CommitRow(commit: GitCommit(hash: "\(index)", parents: [], authorName: "Test", authorEmail: "",
                authoredAt: .distantPast, subject: "Test", refs: []), graph: graph)
        }
        let graph = CommitGraphColors.apply(to: rows)[1].graph
        for dark in [false, true] {
            for selected in [false, true] {
                let renderer = ImageRenderer(content: CommitGraphView(graph: graph, isSelected: selected)
                    .frame(width: 80, height: 96).background(Color.gray)
                    .environment(\.colorScheme, dark ? .dark : .light))
                renderer.scale = 4
                let bitmap = NSBitmapImageRep(cgImage: renderer.cgImage!)
                let colors = [10, 26, 42].map { bitmap.colorAt(x: $0 * 4, y: 18 * 4)!.usingColorSpace(.sRGB)! }
                for index in 0..<colors.count {
                    for other in colors.indices where other > index {
                        let a = colors[index], b = colors[other]
                        let difference = abs(a.redComponent - b.redComponent)
                            + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
                        precondition(difference > 0.3, "Incoming merge paths must render in visibly different colours")
                    }
                }
            }
        }
    }
}

@MainActor
private final class OverlayTestRows: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 60 }
}
