import AppKit

@main
struct ColumnPersistenceTests {
    @MainActor static func main() {
        let suiteName = "DonGit-column-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        func makeTable() -> NSTableView {
            let table = NSTableView()
            for name in ["Graph", "Commit", "Hash", "Author", "Date"] {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
                column.minWidth = 40
                column.maxWidth = 3_000
                column.width = 120
                table.addTableColumn(column)
            }
            return table
        }
        let first = makeTable()
        let original = ColumnPersistenceView(defaults: defaults)
        original.connect(to: first)
        precondition(first.allowsColumnResizing)
        precondition(first.columnAutoresizingStyle == .noColumnAutoresizing)
        first.tableColumns[0].width = 246
        first.tableColumns[1].width = 803
        NotificationCenter.default.post(name: NSTableView.columnDidResizeNotification, object: first)
        precondition(defaults.dictionary(forKey: "commitHistoryColumnWidths")?["Graph"] as? Double == 246)

        let reopened = makeTable()
        let restored = ColumnPersistenceView(defaults: defaults)
        restored.connect(to: reopened)
        precondition(reopened.tableColumns[0].width == 246)
        precondition(reopened.tableColumns[1].width == 803)
        restored.connect(to: reopened)
        precondition(reopened.tableColumns[0].width == 246)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 120))
        let source = ColumnTestRows()
        reopened.dataSource = source
        reopened.rowHeight = 20
        reopened.frame = NSRect(x: 0, y: 0, width: 800, height: 1_200)
        scroll.documentView = reopened
        reopened.reloadData()
        restored.requestSelectionReveal(50)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        precondition(scroll.contentView.bounds.origin.y > 0, "Keyboard selection must scroll into view")
        print("Passed native resize configuration, width saving, and restoration checks.")
    }
}

@MainActor
private final class ColumnTestRows: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 60 }
}
