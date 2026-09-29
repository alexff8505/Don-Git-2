import AppKit
import SwiftUI

@main
struct DiffViewTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let lines = (0..<150).map { index in
            DiffLine(id: index, kind: index == 0 || index == 100 ? .hunk : (index % 2 == 0 ? .deletion : .addition),
                     text: index == 0 || index == 100 ? "@@ -1,1 +1,1 @@" : "A long code line " + String(repeating: "text ", count: 40),
                     oldNumber: index % 2 == 0 ? index : nil, newNumber: index % 2 == 1 ? index : nil)
        }
        let diff = FileDiff(lines: lines, isBinary: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let container = DiffContainerView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 400))
        window.contentView = container
        container.update(diff: diff, presentation: .sideBySide, selectedChangeID: nil)
        container.layoutSubtreeIfNeeded()
        let split = container.subviews.first as! NSSplitView
        split.layoutSubtreeIfNeeded()
        precondition(abs(split.subviews[0].frame.width - 500) < 2, "Side-by-side panes must begin equally sized: \(split.subviews.map(\.frame))")
        let left = split.subviews[0].subviews.first { $0 is NSScrollView } as! NSScrollView
        let right = split.subviews[1].subviews.first { $0 is NSScrollView } as! NSScrollView
        let leftText = left.documentView as! NSTextView
        let rightText = right.documentView as! NSTextView
        precondition(leftText.isSelectable && !leftText.isEditable)
        precondition(leftText.string.split(separator: "\n", omittingEmptySubsequences: false).count == rightText.string.split(separator: "\n", omittingEmptySubsequences: false).count)
        precondition(leftText.frame.width > left.contentSize.width, "Long lines need horizontal scrolling")
        precondition(leftText.frame.height > left.contentSize.height, "Long patches need vertical scrolling")
        left.contentView.scroll(to: NSPoint(x: 0, y: 200))
        left.reflectScrolledClipView(left.contentView)
        precondition(abs(right.contentView.bounds.origin.y - 200) < 1, "Side-by-side vertical scroll must stay synchronized")
        container.update(diff: diff, presentation: .sideBySide, selectedChangeID: 100)
        precondition(leftText.selectedRange().length > 0 && rightText.selectedRange().length > 0)
        precondition(left.contentView.bounds.origin.y > 200, "Keyboard hunk navigation must reveal later changes")
        split.setPosition(400, ofDividerAt: 0)
        container.layoutSubtreeIfNeeded()
        precondition(abs(split.subviews[0].frame.width - 400) < 2, "Dragging the divider must be respected")
        container.update(diff: diff, presentation: .unified, selectedChangeID: nil)
        container.layoutSubtreeIfNeeded()
        let unifiedScroll = container.subviews[0].subviews.first { $0 is NSScrollView } as! NSScrollView
        let unifiedText = unifiedScroll.documentView as! NSTextView
        precondition(unifiedText.string.contains("− ") && unifiedText.string.contains("+ "))
        precondition(unifiedText.usesFindBar)

        let hostingSplit = HostingSplitView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 600))
        hostingSplit.initialFirstSize = 0.4
        hostingSplit.update(first: AnyView(Text("History")), second: AnyView(Text("Select a commit")))
        hostingSplit.layoutSubtreeIfNeeded()
        let originalHeight = hostingSplit.subviews[0].frame.height
        hostingSplit.update(first: AnyView(Text("History")), second: AnyView(List { Text("Many changed files") }))
        hostingSplit.layoutSubtreeIfNeeded()
        precondition(abs(hostingSplit.subviews[0].frame.height - originalHeight) < 1, "Selection must not resize history")
        print("Passed native diff view checks: starting pane sizes, stable history split, read-only selection, aligned rows, horizontal scrolling, synchronized vertical scrolling, hunk reveal, divider resizing, and unified presentation.")
    }
}
