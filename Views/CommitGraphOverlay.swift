import AppKit
import SwiftUI

/// Draw outside the row hosting views: NSTableView clips those views at row
/// boundaries, even when a SwiftUI cell asks to bleed into intercell spacing.
struct CommitGraphOverlay: NSViewRepresentable {
    let rows: [CommitRow]
    let hasLocalChanges: Bool

    func makeNSView(context: Context) -> CommitGraphAttachmentView {
        CommitGraphAttachmentView()
    }

    func updateNSView(_ view: CommitGraphAttachmentView, context: Context) {
        view.update(rows: rows, hasLocalChanges: hasLocalChanges)
    }

    static func dismantleNSView(_ view: CommitGraphAttachmentView, coordinator: ()) {
        view.disconnect()
    }
}

final class CommitGraphAttachmentView: NSView {
    private weak var table: NSTableView?
    private weak var clip: NSClipView?
    private var rows: [CommitRow] = []
    private var sourceRows: [CommitRow] = []
    private var hasLocalChanges = false
    private var workingTree = WorkingTreeGraphLayout(rows: [], hasLocalChanges: false)
    private var connectionScheduled = false
    private var columnWidthObservation: NSKeyValueObservation?
    private let overlay = GraphHostingView(rootView: CommitGraphLayer(items: []))

    func update(rows: [CommitRow], hasLocalChanges: Bool) {
        if sourceRows != rows || self.hasLocalChanges != hasLocalChanges {
            sourceRows = rows
            self.rows = CommitGraphColors.apply(to: rows)
            self.hasLocalChanges = hasLocalChanges
            workingTree = WorkingTreeGraphLayout(rows: rows, hasLocalChanges: hasLocalChanges)
        }
        connectWhenReady()
        redraw()
        // SwiftUI can still be changing native row heights during this update.
        DispatchQueue.main.async { [weak self] in self?.redraw() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { disconnect() } else { connectWhenReady() }
    }

    private func connectWhenReady(attempt: Int = 0) {
        guard !connectionScheduled, window != nil else { return }
        connectionScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.05)) { [weak self] in
            guard let self else { return }
            self.connectionScheduled = false
            guard let root = self.window?.contentView else { return }
            if let table = self.findHistoryTable(in: root), let clip = table.enclosingScrollView?.contentView {
                self.connect(to: table, clip: clip)
            } else if attempt < 10 {
                self.connectWhenReady(attempt: attempt + 1)
            }
        }
    }

    private func findHistoryTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView, table.tableColumns.count == 5 { return table }
        for child in view.subviews {
            if let table = findHistoryTable(in: child) { return table }
        }
        return nil
    }

    func connect(to table: NSTableView, clip: NSClipView) {
        guard self.table !== table || self.clip !== clip else { redraw(); return }
        disconnect()
        self.table = table
        self.clip = clip
        clip.addSubview(overlay, positioned: .above, relativeTo: table)
        for view in [table, clip] {
            view.postsFrameChangedNotifications = true
            view.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.frameDidChangeNotification, object: view)
            NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: view)
        }
        for name in [NSTableView.selectionDidChangeNotification, NSTableView.columnDidResizeNotification,
                     NSTableView.columnDidMoveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: name, object: table)
        }
        // SwiftUI can change NSTableColumn.width without posting AppKit's
        // resize notification (the persistence bridge handles the same case).
        columnWidthObservation = table.tableColumns.first?.observe(\.width, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.redraw() }
        }
        redraw()
    }

    func disconnect() {
        NotificationCenter.default.removeObserver(self)
        columnWidthObservation = nil
        overlay.removeFromSuperview()
        table = nil
        clip = nil
    }

    @objc func redraw() {
        guard let table, let clip, table.numberOfColumns > 0 else { return }
        let column = table.rect(ofColumn: 0)
        let viewport = table.convert(clip.bounds, from: clip)
        // A sibling of the document view sits above all native rows and scrolls
        // with the clip view. Its bounds contain only the visible graph column.
        let frame = NSRect(x: column.minX, y: viewport.minY, width: column.width, height: viewport.height)
        overlay.frame = clip.convert(frame, from: table)
        let visible = table.rows(in: viewport)
        let expectedCount = rows.count + (hasLocalChanges ? 1 : 0)
        guard visible.location != NSNotFound, table.numberOfRows == expectedCount else {
            overlay.rootView = CommitGraphLayer(items: [])
            return
        }
        var items: [CommitGraphLayer.Item] = []
        for index in visible.location..<min(NSMaxRange(visible), expectedCount) {
            let row = table.rect(ofRow: index)
            let previous = index > 0 ? table.rect(ofRow: index - 1) : nil
            let next = index + 1 < expectedCount ? table.rect(ofRow: index + 1) : nil
            let span = CommitGraphRowSpan(row: row, previous: previous, next: next)
            let cell = table.frameOfCell(atColumn: 0, row: index)
            let rect = CGRect(x: cell.minX - frame.minX, y: span.top - frame.minY,
                              width: max(0, column.maxX - cell.minX), height: span.bottom - span.top)
            let commitIndex = index - (hasLocalChanges ? 1 : 0)
            let commit = commitIndex >= 0 ? rows[commitIndex] : nil
            items.append(CommitGraphLayer.Item(id: index, rect: rect, nodeCenter: row.midY - span.top,
                graph: commit?.graph, isSelected: table.isRowSelected(index),
                connection: commit.flatMap { workingTree.connections[$0.id] },
                graphInset: workingTree.graphInset, connectsToHEAD: !workingTree.connections.isEmpty))
        }
        overlay.rootView = CommitGraphLayer(items: items)
    }
}

private final class GraphHostingView: NSHostingView<CommitGraphLayer> {
    override var isOpaque: Bool { false }
    // Preserve native row selection, context menus, column dragging and scrolling.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct CommitGraphLayer: View {
    struct Item: Identifiable {
        let id: Int
        let rect: CGRect
        let nodeCenter: CGFloat
        let graph: CommitGraphState?
        let isSelected: Bool
        let connection: WorkingTreeGraphConnection?
        let graphInset: CGFloat
        let connectsToHEAD: Bool
    }

    let items: [Item]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                Group {
                    if let graph = item.graph {
                        CommitGraphView(graph: graph, isSelected: item.isSelected,
                            workingTreeConnection: item.connection, graphInset: item.graphInset,
                            nodeCenter: item.nodeCenter)
                    } else {
                        WorkingTreeGraphView(connectsToHEAD: item.connectsToHEAD, nodeCenter: item.nodeCenter)
                    }
                }
                .frame(width: item.rect.width, height: item.rect.height)
                .position(x: item.rect.midX, y: item.rect.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
