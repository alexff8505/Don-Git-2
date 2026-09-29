import AppKit
import SwiftUI

/// Keep SwiftUI's native table and use AppKit's column resize notifications.
struct CommitTableColumnPersistence: NSViewRepresentable {
    func makeNSView(context: Context) -> ColumnPersistenceView {
        ColumnPersistenceView()
    }

    func updateNSView(_ nsView: ColumnPersistenceView, context: Context) {
        nsView.connectWhenReady()
    }
}

final class ColumnPersistenceView: NSView {
    private static let widthsKey = "commitHistoryColumnWidths"
    private static let columnNames: Set<String> = ["Graph", "Commit", "Hash", "Author", "Date"]
    private weak var table: NSTableView?
    private var connectionScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        connectWhenReady()
    }

    func connectWhenReady(attempt: Int = 0) {
        guard !connectionScheduled, window != nil else { return }
        connectionScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.05)) { [weak self] in
            guard let self else { return }
            self.connectionScheduled = false
            guard let root = self.window?.contentView else { return }
            if let table = self.findHistoryTable(in: root) {
                self.connect(to: table)
            } else if attempt < 10 {
                self.connectWhenReady(attempt: attempt + 1)
            }
        }
    }

    private func findHistoryTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView,
           Set(table.tableColumns.map { $0.headerCell.stringValue }) == Self.columnNames {
            return table
        }
        for child in view.subviews {
            if let table = findHistoryTable(in: child) { return table }
        }
        return nil
    }

    private func connect(to table: NSTableView) {
        guard self.table !== table else { return }
        NotificationCenter.default.removeObserver(self, name: NSTableView.columnDidResizeNotification, object: self.table)
        self.table = table
        table.columnAutoresizingStyle = .noColumnAutoresizing
        let widths = UserDefaults.standard.dictionary(forKey: Self.widthsKey) ?? [:]
        for column in table.tableColumns {
            column.resizingMask = .userResizingMask
            if let width = widths[column.headerCell.stringValue] as? NSNumber,
               width.doubleValue.isFinite {
                column.width = min(column.maxWidth, max(column.minWidth, CGFloat(width.doubleValue)))
            }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(columnsDidResize(_:)),
            name: NSTableView.columnDidResizeNotification, object: table
        )
    }

    @objc private func columnsDidResize(_ notification: Notification) {
        guard let table else { return }
        let widths = Dictionary(uniqueKeysWithValues: table.tableColumns.map {
            ($0.headerCell.stringValue, Double($0.width))
        })
        UserDefaults.standard.set(widths, forKey: Self.widthsKey)
    }
}
