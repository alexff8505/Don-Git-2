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
        print("Passed native resize configuration, width saving, and restoration checks.")
    }
}
