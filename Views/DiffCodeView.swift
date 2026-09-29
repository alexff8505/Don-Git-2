import AppKit
import SwiftUI

/// Native, read-only text views retain macOS selection, copy, find, and scrolling behavior.
struct DiffCodeView: NSViewRepresentable {
    let diff: FileDiff
    let presentation: DiffPresentation
    let selectedChangeID: Int?
    var wordWrap = false

    func makeNSView(context: Context) -> DiffContainerView { DiffContainerView() }

    func updateNSView(_ view: DiffContainerView, context: Context) {
        view.update(diff: diff, presentation: presentation, selectedChangeID: selectedChangeID, wordWrap: wordWrap)
    }
}

@MainActor
final class DiffContainerView: NSView {
    var defaults: UserDefaults = .standard
    private var displayedDiff: FileDiff?
    private var presentation: DiffPresentation?
    private var selectedChangeID: Int?
    private var panes: [DiffTextPane] = []
    private var splitView: DiffSplitView?
    private var scrollObservers: [DiffScrollObservation] = []
    private var synchronizingScroll = false
    private var wordWrap = false
    private var fittedWidths: [CGFloat] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        NotificationCenter.default.addObserver(self, selector: #selector(focusCode), name: .focusCodeDiff, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func focusCode() {
        guard window?.isKeyWindow == true else { return }
        panes.first?.focusCode()
    }

    override func layout() {
        super.layout()
        splitView?.balanceIfNeeded()
        for pane in panes { pane.layoutSubtreeIfNeeded() }
        fitRowsIfNeeded()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let displayedDiff, let presentation { render(displayedDiff, presentation: presentation) }
    }

    func update(diff: FileDiff, presentation: DiffPresentation, selectedChangeID: Int?, wordWrap: Bool = false) {
        let contentChanged = displayedDiff != diff || self.presentation != presentation || self.wordWrap != wordWrap
        if contentChanged {
            displayedDiff = diff
            self.presentation = presentation
            self.wordWrap = wordWrap
            configurePanes(presentation)
            render(diff, presentation: presentation)
        }
        if self.selectedChangeID != selectedChangeID || contentChanged {
            self.selectedChangeID = selectedChangeID
            if let selectedChangeID {
                for pane in panes { pane.revealChange(selectedChangeID) }
            }
        }
    }

    private func fitRowsIfNeeded() {
        let widths = panes.map { $0.scrollView.contentSize.width }
        guard widths != fittedWidths else { return }
        fittedWidths = widths
        let heights = panes.map { $0.prepareLayout(wordWrap: wordWrap) }
        if heights.count == 2 {
            let shared = zip(heights[0], heights[1]).map { max($0, $1) }
            for (index, pane) in panes.enumerated() {
                pane.alignRows(to: shared, naturalHeights: heights[index])
            }
        }
        for pane in panes { pane.updateRowGeometry() }
    }

    private func configurePanes(_ presentation: DiffPresentation) {
        scrollObservers.removeAll()
        subviews.forEach { $0.removeFromSuperview() }
        panes = []
        fittedWidths = []
        splitView = nil
        if presentation == .unified {
            let pane = DiffTextPane(title: nil, accessibilityName: "Unified code diff")
            pane.frame = bounds
            pane.autoresizingMask = [.width, .height]
            addSubview(pane)
            panes = [pane]
        } else {
            let split = DiffSplitView(frame: bounds)
            split.defaults = defaults
            split.isVertical = true
            split.dividerStyle = .thin
            split.autoresizingMask = [.width, .height]
            let left = DiffTextPane(title: "Before", accessibilityName: "Before code changes")
            let right = DiffTextPane(title: "After", accessibilityName: "After code changes")
            left.frame = NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
            right.frame = NSRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height)
            split.addArrangedSubview(left)
            split.addArrangedSubview(right)
            addSubview(split)
            splitView = split
            panes = [left, right]
            split.balanceIfNeeded()
            // Synchronize vertical positions, while keeping horizontal scrolling independent.
            for pane in panes {
                let clip = pane.scrollView.contentView
                clip.postsBoundsChangedNotifications = true
                let observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                     object: clip, queue: .main) { [weak self, weak clip] _ in
                    MainActor.assumeIsolated {
                        guard let self, let clip, !self.synchronizingScroll else { return }
                        self.synchronizingScroll = true
                        for other in self.panes where other.scrollView.contentView !== clip {
                            let otherClip = other.scrollView.contentView
                            otherClip.scroll(to: NSPoint(x: otherClip.bounds.origin.x, y: clip.bounds.origin.y))
                            other.scrollView.reflectScrolledClipView(otherClip)
                        }
                        self.synchronizingScroll = false
                    }
                }
                scrollObservers.append(DiffScrollObservation(observer))
            }
        }
        for pane in panes {
            pane.widthDidChange = { [weak self] in self?.needsLayout = true }
        }
    }

    private func render(_ diff: FileDiff, presentation: DiffPresentation) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if presentation == .unified {
                panes.first?.render(diff.lines.map { ($0, $0.oldNumber, $0.newNumber, $0.id) }, unified: true)
            } else {
                let split = diff.splitLines
                panes[0].render(split.map { ($0.left, $0.left?.oldNumber, nil, $0.left?.id ?? $0.right!.id) }, unified: false)
                panes[1].render(split.map { ($0.right, $0.right?.newNumber, nil, $0.left?.id ?? $0.right!.id) }, unified: false)
            }
        }
        fittedWidths = []
        needsLayout = true
        layoutSubtreeIfNeeded()
        for pane in panes { pane.resetScroll() }
    }

}

/// Size against the splitter's own bounds after AppKit resizes it, rather than its host's pending frame.
@MainActor
private final class DiffSplitView: NSSplitView, NSSplitViewDelegate {
    var defaults: UserDefaults = .standard
    private let fractionKey = "codeDiffPaneFraction"
    private var lastWidth: CGFloat = 0
    private var balancing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        balanceIfNeeded()
    }

    override func layout() {
        super.layout()
        balanceIfNeeded()
    }

    override func adjustSubviews() {
        super.adjustSubviews()
        balanceIfNeeded()
    }

    func balanceIfNeeded() {
        guard !balancing, subviews.count == 2, bounds.width > 0,
              lastWidth != bounds.width || subviews.contains(where: { $0.frame.width < 80 }) else { return }
        balancing = true
        defer { balancing = false }
        lastWidth = bounds.width
        let saved = defaults.object(forKey: fractionKey) as? Double ?? 0.5
        let fraction = saved.isFinite ? min(0.9, max(0.1, saved)) : 0.5
        setPosition(bounds.width * fraction, ofDividerAt: 0)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !balancing, lastWidth == bounds.width, bounds.width > 0,
              subviews.count == 2, subviews.allSatisfy({ $0.frame.width >= 80 }) else { return }
        defaults.set(Double(subviews[0].frame.width / bounds.width), forKey: fractionKey)
    }
}

/// The immutable token can be released off the main actor; NotificationCenter removal is thread-safe.
private final class DiffScrollObservation: @unchecked Sendable {
    private let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

@MainActor
private final class DiffTextPane: NSView {
    let scrollView = NSScrollView()
    private let textView = DiffTextView()
    private var documentWidth: CGFloat = 0
    private var documentHeight: CGFloat = 0
    private var changeRanges: [Int: NSRange] = [:]
    private var header: NSTextField?
    private var lineNumberRuler: DiffLineNumberRuler!
    private let oldSide: Bool?
    private var rowRanges: [NSRange] = []
    private var wordWrap = false
    private var lastContentWidth: CGFloat = -1
    var widthDidChange: (() -> Void)?
    override var isFlipped: Bool { true }

    init(title: String?, accessibilityName: String) {
        oldSide = title.map { $0 == "Before" }
        super.init(frame: .zero)
        let header = title.map { NSTextField(labelWithString: $0) }
        self.header = header
        if let header {
            header.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
            header.textColor = .secondaryLabelColor
            addSubview(header)
        }
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel(accessibilityName)
        scrollView.documentView = textView
        lineNumberRuler = DiffLineNumberRuler(scrollView: scrollView, orientation: .verticalRuler)
        lineNumberRuler.clipsToBounds = true
        lineNumberRuler.clientView = textView
        scrollView.verticalRulerView = lineNumberRuler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        header?.frame = NSRect(x: 12, y: 6, width: max(0, bounds.width - 24), height: 18)
        let headerHeight: CGFloat = header == nil ? 0 : 28
        scrollView.frame = NSRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))
        sizeDocument()
        if lastContentWidth != scrollView.contentSize.width {
            lastContentWidth = scrollView.contentSize.width
            widthDidChange?()
        }
    }

    func render(_ rows: [(DiffLine?, Int?, Int?, Int)], unified: Bool) {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = DiffTextView.lineHeight
        paragraph.maximumLineHeight = DiffTextView.lineHeight
        paragraph.lineBreakMode = .byClipping
        paragraph.tabStops = []
        paragraph.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: font]).width * 4
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
        let result = NSMutableAttributedString()
        var backgrounds: [NSColor?] = []
        changeRanges = [:]
        rowRanges = []
        documentWidth = 0
        for (line, _, _, targetID) in rows {
            let prefix: String
            switch line?.kind {
            case .addition: prefix = "+ "
            case .deletion: prefix = "− "
            default: prefix = "  "
            }
            let text = prefix + (line?.sectionTitle(oldSide: oldSide) ?? "") + "\n"
            let attributed = NSMutableAttributedString(string: text, attributes: attributes)
            let color: NSColor?
            switch line?.kind {
            case .addition: color = NSColor.systemGreen.withAlphaComponent(0.14)
            case .deletion: color = NSColor.systemRed.withAlphaComponent(0.14)
            case .hunk:
                color = NSColor.windowBackgroundColor
                attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .medium),
                                        range: NSRange(location: 0, length: attributed.length))
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                        range: NSRange(location: 0, length: attributed.length))
            case .notice:
                color = nil
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                        range: NSRange(location: 0, length: attributed.length))
            default: color = nil
            }
            changeRanges[targetID] = NSRange(location: result.length, length: attributed.length - 1)
            rowRanges.append(NSRange(location: result.length, length: attributed.length))
            result.append(attributed)
            backgrounds.append(color)
            // NSString measurement includes tab expansion through the paragraph style.
            documentWidth = max(documentWidth, attributed.size().width)
        }
        textView.textStorage?.setAttributedString(result)
        textView.rowBackgrounds = backgrounds
        lineNumberRuler.update(numbers: rows.map { ($0.1, $0.2) }, backgrounds: backgrounds, unified: unified)
        documentWidth += 32
        documentHeight = CGFloat(rows.count) * DiffTextView.lineHeight + 32
        sizeDocument()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        textView.needsDisplay = true
    }

    func sizeDocument() {
        // Tile immediately so the ruler reserves space before TextKit measures wrapping.
        scrollView.tile()
        let coveredWidth = max(0, lineNumberRuler.frame.maxX - scrollView.contentView.frame.minX)
        textView.textContainerInset.width = 8 + coveredWidth
        let width = wordWrap ? scrollView.contentSize.width : max(documentWidth, scrollView.contentSize.width)
        textView.textContainer?.containerSize = NSSize(width: wordWrap ? max(1, width - textView.textContainerInset.width * 2) : CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.setFrameSize(NSSize(width: max(1, width),
                                     height: max(documentHeight, scrollView.contentSize.height)))
    }

    /// Measure TextKit's real wrapped paragraphs, then pad the shorter side of each diff row.
    func prepareLayout(wordWrap: Bool) -> [CGFloat] {
        self.wordWrap = wordWrap
        scrollView.hasHorizontalScroller = !wordWrap
        textView.isHorizontallyResizable = !wordWrap
        if wordWrap { scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y)) }
        guard let storage = textView.textStorage else { return [] }
        storage.beginEditing()
        for range in rowRanges {
            let style = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
            style.lineBreakMode = wordWrap ? .byWordWrapping : .byClipping
            style.paragraphSpacing = 0
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        storage.endEditing()
        sizeDocument()
        return rowRects().map(\.height)
    }

    func alignRows(to heights: [CGFloat], naturalHeights: [CGFloat]) {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        for (index, range) in rowRanges.enumerated() {
            let padding = heights[index] - naturalHeights[index]
            guard padding > 0 else { continue }
            let style = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
            style.paragraphSpacing = padding
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        storage.endEditing()
    }

    private func rowRects() -> [NSRect] {
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return [] }
        manager.ensureLayout(for: container)
        let starts = rowRanges.map { range in
            let glyph = manager.glyphIndexForCharacter(at: range.location)
            return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + textView.textContainerInset.height
        }
        let end = (manager.extraLineFragmentTextContainer === container
                   ? manager.extraLineFragmentRect.minY : manager.usedRect(for: container).maxY)
            + textView.textContainerInset.height
        return starts.enumerated().map { index, y in
            NSRect(x: 0, y: y, width: textView.bounds.width,
                   height: max(DiffTextView.lineHeight, (index + 1 < starts.count ? starts[index + 1] : end) - y))
        }
    }

    func updateRowGeometry() {
        let rects = rowRects()
        textView.rowRects = rects
        lineNumberRuler.rowRects = rects
        documentHeight = (rects.last?.maxY ?? 0) + 24
        sizeDocument()
        textView.needsDisplay = true
        lineNumberRuler.needsDisplay = true
    }

    func revealChange(_ id: Int) {
        guard let range = changeRanges[id] else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    func resetScroll() {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func focusCode() { window?.makeFirstResponder(textView) }
}

/// A standard scroll-view ruler keeps line numbers out of selection and horizontal scrolling.
@MainActor
final class DiffLineNumberRuler: NSRulerView {
    var rowRects: [NSRect] = []
    private var numbers: [(Int?, Int?)] = []
    private var backgrounds: [NSColor?] = []
    private var unified = false
    private var columnWidth: CGFloat = 34
    override var isFlipped: Bool { true }

    func update(numbers: [(Int?, Int?)], backgrounds: [NSColor?], unified: Bool) {
        self.numbers = numbers
        self.backgrounds = backgrounds
        self.unified = unified
        let digits = max(3, numbers.flatMap { [$0.0, $0.1].compactMap { $0 } }.map { String($0).count }.max() ?? 3)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        columnWidth = ceil((String(repeating: "0", count: digits) as NSString).size(withAttributes: [.font: font]).width) + 14
        ruleThickness = columnWidth * (unified ? 2 : 1)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(rect: bounds).addClip()
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        guard let textView = clientView as? NSTextView else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        for (index, row) in rowRects.enumerated() {
            let rect = convert(row, from: textView)
            guard rect.maxY > dirtyRect.minY, rect.minY < dirtyRect.maxY, numbers.indices.contains(index) else { continue }
            let y = rect.minY
            if let color = backgrounds[index] {
                color.setFill()
                NSRect(x: 0, y: y, width: bounds.width, height: rect.height).fill()
            }
            let values = unified ? [numbers[index].0, numbers[index].1] : [numbers[index].0]
            for (column, value) in values.enumerated() {
                guard let value else { continue }
                let text = String(value) as NSString
                let width = text.size(withAttributes: attributes).width
                text.draw(at: NSPoint(x: CGFloat(column + 1) * columnWidth - width - 7, y: y + 1),
                          withAttributes: attributes)
            }
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.width - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        if unified {
            NSRect(x: columnWidth, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        }
    }
}

@MainActor
private final class DiffTextView: NSTextView {
    static let lineHeight: CGFloat = 18
    var rowBackgrounds: [NSColor?] = []
    var rowRects: [NSRect] = []

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        for (index, row) in rowRects.enumerated() where row.intersects(rect) {
            guard let color = rowBackgrounds[index] else { continue }
            color.setFill()
            NSRect(x: rect.minX, y: row.minY, width: rect.width, height: row.height).fill()
        }
    }
}
