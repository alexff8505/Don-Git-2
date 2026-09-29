import AppKit
import SwiftUI

/// Keep SwiftUI's native table and use AppKit's column resize notifications.
struct CommitTableColumnPersistence: NSViewRepresentable {
    var selectedRowIndex: Int? = nil
    func makeNSView(context: Context) -> ColumnPersistenceView {
        ColumnPersistenceView()
    }

    func updateNSView(_ nsView: ColumnPersistenceView, context: Context) {
        nsView.requestSelectionReveal(selectedRowIndex)
        nsView.connectWhenReady()
    }
}

final class ColumnPersistenceView: NSView {
    private static let widthsKey = "commitHistoryColumnWidths"
    private static let columnNames = ["Graph", "Commit", "Hash", "Author", "Date"]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        defaults = .standard
        super.init(coder: coder)
    }

    private weak var table: NSTableView?
    private var connectionScheduled = false
    private var requestedRow: Int?
    private var restoringWidths = false
    private var widthObservers: [NSKeyValueObservation] = []

    func requestSelectionReveal(_ row: Int?) {
        guard requestedRow != row else { return }
        requestedRow = row
        // SwiftUI applies its table selection during the same update; reveal it afterwards.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.requestedRow == row else { return }
            self.revealRequestedSelection()
        }
    }

    private func revealRequestedSelection() {
        guard let table, let requestedRow, requestedRow >= 0, requestedRow < table.numberOfRows else { return }
        table.scrollRowToVisible(requestedRow)
    }

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
           table.tableColumns.count == Self.columnNames.count {
            return table
        }
        for child in view.subviews {
            if let table = findHistoryTable(in: child) { return table }
        }
        return nil
    }

    func connect(to table: NSTableView) {
        guard self.table !== table else { return }
        NotificationCenter.default.removeObserver(self, name: NSTableView.columnDidResizeNotification, object: self.table)
        widthObservers.removeAll()
        self.table = table
        restoringWidths = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnResizing = true
        let widths = defaults.dictionary(forKey: Self.widthsKey) ?? [:]
        restore(widths, to: table)
        // SwiftUI finishes arranging its table after attaching the native backing view.
        // Apply the saved widths after that pass, without saving those initial layout changes.
        DispatchQueue.main.async { [weak self, weak table] in
            guard let self, let table, self.table === table else { return }
            table.window?.contentView?.layoutSubtreeIfNeeded()
            self.restore(widths, to: table)
            self.restoringWidths = false
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(columnsDidResize(_:)),
            name: NSTableView.columnDidResizeNotification, object: table
        )
        // SwiftUI's header resizing can set NSTableColumn.width without the table's resize notification.
        widthObservers = table.tableColumns.map { column in
            column.observe(\.width, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.saveWidths() }
            }
        }
        revealRequestedSelection()
    }

    private func restore(_ widths: [String: Any], to table: NSTableView) {
        for (index, column) in table.tableColumns.enumerated() {
            column.resizingMask = .userResizingMask
            if let width = widths[Self.columnNames[index]] as? NSNumber,
               width.doubleValue.isFinite {
                column.width = min(column.maxWidth, max(column.minWidth, CGFloat(width.doubleValue)))
            }
        }
    }

    @objc private func columnsDidResize(_ notification: Notification) {
        saveWidths()
    }

    private func saveWidths() {
        guard !restoringWidths, let table else { return }
        let widths = Dictionary(uniqueKeysWithValues: table.tableColumns.enumerated().map { index, column in
            (Self.columnNames[index], Double(column.width))
        })
        defaults.set(widths, forKey: Self.widthsKey)
    }
}
