import AppKit
import SwiftUI

@main
struct DiffViewTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "DonGit-diff-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let lines = (0..<150).map { index in
            DiffLine(id: index, kind: index == 0 || index == 100 ? .hunk : (index % 2 == 0 ? .deletion : .addition),
                     text: index == 0 || index == 100 ? "@@ -1,1 +1,1 @@" : "A long code line " + String(repeating: "text ", count: 40),
                     oldNumber: index % 2 == 0 ? index : nil, newNumber: index % 2 == 1 ? index : nil)
        }
        let diff = FileDiff(lines: lines, isBinary: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let container = DiffContainerView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 400))
        container.defaults = defaults
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
        precondition(unifiedScroll.rulersVisible && unifiedScroll.verticalRulerView is DiffLineNumberRuler)
        let gutter = unifiedScroll.verticalRulerView!
        let gutterX = gutter.frame.origin.x
        unifiedScroll.contentView.scroll(to: NSPoint(x: 200, y: 0))
        unifiedScroll.reflectScrolledClipView(unifiedScroll.contentView)
        precondition(gutter.frame.origin.x == gutterX, "Line numbers must stay fixed when code scrolls horizontally")
        // AppKit can supply a dirty rectangle beyond a ruler's bounds. Its drawing must
        // leave neighbouring code and toolbar pixels alone, even in that case.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(gutter.bounds.width) + 20,
                                     pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.magenta.setFill()
        let oversized = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        oversized.fill()
        gutter.draw(oversized)
        NSGraphicsContext.restoreGraphicsState()
        let outside = bitmap.colorAt(x: Int(gutter.bounds.width) + 5, y: 10)!.usingColorSpace(.deviceRGB)!
        precondition(outside.redComponent > 0.99 && outside.blueComponent > 0.99 && outside.greenComponent < 0.01,
                     "Gutter drawing must not cover adjacent code")
        precondition(!unifiedText.string.contains("@@"), "Readable section ranges replace raw patch headers")
        precondition(unifiedText.string.hasPrefix("  Line 1\n+ A long code line"), "Copied code must not contain display line numbers")
        let shifted = DiffLine(id: 0, kind: .hunk, text: "@@ -138,12 +141,15 @@ function example()", oldNumber: nil, newNumber: nil)
        precondition(shifted.sectionTitle() == "Before: Lines 138–149 · After: Lines 141–155")
        precondition(shifted.sectionTitle(oldSide: true) == "Lines 138–149")
        precondition(shifted.sectionTitle(oldSide: false) == "Lines 141–155")
        let added = DiffLine(id: 0, kind: .hunk, text: "@@ -0,0 +1,2 @@", oldNumber: nil, newNumber: nil)
        precondition(added.sectionTitle() == "Before: No lines · After: Lines 1–2")
        container.update(diff: diff, presentation: .sideBySide, selectedChangeID: nil)
        let switchedSplit = container.subviews.first as! NSSplitView
        precondition(abs(switchedSplit.subviews[0].frame.width - 400) < 2,
                     "Switching modes must restore the resized panes before the next layout pass")
        switchedSplit.setFrameSize(NSSize(width: 600, height: 400))
        container.layoutSubtreeIfNeeded()
        precondition(abs(switchedSplit.subviews[0].frame.width - 240) < 2,
                     "The divider must follow the splitter's actual width during hosted layout")

        let wrapDiff = FileDiff(lines: [
            DiffLine(id: 0, kind: .hunk, text: "@@ -1,2 +1,2 @@", oldNumber: nil, newNumber: nil),
            DiffLine(id: 1, kind: .deletion, text: "Short before", oldNumber: 1, newNumber: nil),
            DiffLine(id: 2, kind: .addition, text: String(repeating: "long replacement code ", count: 30), oldNumber: nil, newNumber: 1),
            DiffLine(id: 3, kind: .context, text: "Following context", oldNumber: 2, newNumber: 2)
        ], isBinary: false)
        container.update(diff: wrapDiff, presentation: .sideBySide, selectedChangeID: nil, wordWrap: true)
        container.layoutSubtreeIfNeeded()
        let wrappedSplit = container.subviews.first as! NSSplitView
        func wrappedScroll(_ index: Int) -> NSScrollView {
            wrappedSplit.subviews[index].subviews.first { $0 is NSScrollView } as! NSScrollView
        }
        func checkWrappedAlignment() {
            let before = wrappedScroll(0)
            let after = wrappedScroll(1)
            precondition(!before.hasHorizontalScroller && !after.hasHorizontalScroller)
            let beforeText = before.documentView as! NSTextView
            precondition(before.contentView.frame.minX + beforeText.textContainerOrigin.x >= before.verticalRulerView!.ruleThickness,
                         "The ruler must not cover code when AppKit overlays it on the content")
            let beforeRects = (before.verticalRulerView as! DiffLineNumberRuler).rowRects
            let afterRects = (after.verticalRulerView as! DiffLineNumberRuler).rowRects
            precondition(beforeRects[1].height > 18, "Replacement must wrap to multiple visual lines")
            for (left, right) in zip(beforeRects, afterRects) {
                precondition(abs(left.minY - right.minY) < 1 && abs(left.height - right.height) < 1,
                             "Wrapped side-by-side rows and gutters must remain aligned: \(beforeRects), \(afterRects)")
            }
            precondition(abs(before.documentView!.frame.width - before.contentSize.width) < 1)
        }
        checkWrappedAlignment()
        wrappedSplit.setPosition(300, ofDividerAt: 0)
        container.layoutSubtreeIfNeeded()
        checkWrappedAlignment()
        container.update(diff: wrapDiff, presentation: .unified, selectedChangeID: nil, wordWrap: true)
        container.layoutSubtreeIfNeeded()
        let wrappedUnified = container.subviews[0].subviews.first { $0 is NSScrollView } as! NSScrollView
        let wrappedText = (wrappedUnified.documentView as! NSTextView).string
        precondition((wrappedUnified.verticalRulerView as! DiffLineNumberRuler).rowRects[2].height > 18)
        container.update(diff: wrapDiff, presentation: .unified, selectedChangeID: nil, wordWrap: false)
        container.layoutSubtreeIfNeeded()
        let unwrapped = container.subviews[0].subviews.first { $0 is NSScrollView } as! NSScrollView
        precondition(unwrapped.hasHorizontalScroller && unwrapped.documentView!.frame.width > unwrapped.contentSize.width)
        precondition((unwrapped.documentView as! NSTextView).string == wrappedText, "Wrapping must not change copied code")
        let unwrappedRects = (unwrapped.verticalRulerView as! DiffLineNumberRuler).rowRects
        precondition(unwrappedRects.allSatisfy { abs($0.height - 18) < 1 }, "Unwrapped row heights: \(unwrappedRects)")

        let hostingSplit = HostingSplitView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 600))
        hostingSplit.initialFirstSize = 0.4
        hostingSplit.defaults = defaults
        hostingSplit.persistenceKey = "testHistorySplit"
        hostingSplit.update(first: AnyView(Text("History")), second: AnyView(Text("Select a commit")))
        hostingSplit.layoutSubtreeIfNeeded()
        let originalHeight = hostingSplit.subviews[0].frame.height
        hostingSplit.update(first: AnyView(Text("History")), second: AnyView(List { Text("Many changed files") }))
        hostingSplit.layoutSubtreeIfNeeded()
        precondition(abs(hostingSplit.subviews[0].frame.height - originalHeight) < 1, "Selection must not resize history")
        hostingSplit.setPosition(320, ofDividerAt: 0)
        let reopenedSplit = HostingSplitView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 600))
        reopenedSplit.defaults = defaults
        reopenedSplit.persistenceKey = "testHistorySplit"
        reopenedSplit.update(first: AnyView(Text("History")), second: AnyView(Text("Details")))
        reopenedSplit.layoutSubtreeIfNeeded()
        precondition(abs(reopenedSplit.subviews[0].frame.height - 320) < 1, "Pane sizes must survive reopening")
        func fileSplit() -> HostingSplitView {
            let view = HostingSplitView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 600))
            view.isVertical = true
            view.defaults = defaults
            view.persistenceKey = "testFileWidth"
            view.initialFirstSize = 270
            view.update(first: AnyView(Text("Files")), second: AnyView(Text("Code")))
            view.layoutSubtreeIfNeeded()
            return view
        }
        let originalFiles = fileSplit()
        originalFiles.setPosition(350, ofDividerAt: 0)
        precondition(abs(fileSplit().subviews[0].frame.width - 350) < 1, "Changed-file width must survive reopening")
        print("Passed native diff view checks, including wrap toggling, wrapped row alignment, resizing, gutters, and unchanged copied text.")
    }
}
