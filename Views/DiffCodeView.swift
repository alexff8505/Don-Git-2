import AppKit
import SwiftUI

/// Native, read-only text views retain macOS selection, copy, find, and scrolling behavior.
struct DiffCodeView: NSViewRepresentable {
    let diff: FileDiff
    let presentation: DiffPresentation
    let selectedChangeID: Int?

    func makeNSView(context: Context) -> DiffContainerView { DiffContainerView() }

    func updateNSView(_ view: DiffContainerView, context: Context) {
        view.update(diff: diff, presentation: presentation, selectedChangeID: selectedChangeID)
    }
}

@MainActor
final class DiffContainerView: NSView {
    private var displayedDiff: FileDiff?
    private var presentation: DiffPresentation?
    private var selectedChangeID: Int?
    private var panes: [DiffTextPane] = []
    private var splitView: NSSplitView?
    private var scrollObservers: [DiffScrollObservation] = []
    private var synchronizingScroll = false
    private var needsInitialSplit = false
    private var lastSplitWidth: CGFloat = 0

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
        if (needsInitialSplit || lastSplitWidth != bounds.width), bounds.width > 0, let splitView {
            splitView.setPosition(bounds.width / 2, ofDividerAt: 0)
            needsInitialSplit = false
            lastSplitWidth = bounds.width
        }
        for pane in panes { pane.sizeDocument() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let displayedDiff, let presentation { render(displayedDiff, presentation: presentation) }
    }

    func update(diff: FileDiff, presentation: DiffPresentation, selectedChangeID: Int?) {
        let contentChanged = displayedDiff != diff || self.presentation != presentation
        if contentChanged {
            displayedDiff = diff
            self.presentation = presentation
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

    private func configurePanes(_ presentation: DiffPresentation) {
        scrollObservers.removeAll()
        subviews.forEach { $0.removeFromSuperview() }
        panes = []
        splitView = nil
        lastSplitWidth = 0
        if presentation == .unified {
            let pane = DiffTextPane(title: nil, accessibilityName: "Unified code diff")
            pane.frame = bounds
            pane.autoresizingMask = [.width, .height]
            addSubview(pane)
            panes = [pane]
        } else {
            let split = NSSplitView(frame: bounds)
            split.isVertical = true
            split.dividerStyle = .thin
            split.autoresizingMask = [.width, .height]
            let left = DiffTextPane(title: "Before", accessibilityName: "Before code changes")
            let right = DiffTextPane(title: "After", accessibilityName: "After code changes")
            split.addArrangedSubview(left)
            split.addArrangedSubview(right)
            addSubview(split)
            splitView = split
            panes = [left, right]
            needsInitialSplit = true
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
        needsLayout = true
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
    override var isFlipped: Bool { true }

    init(title: String?, accessibilityName: String) {
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
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        header?.frame = NSRect(x: 12, y: 6, width: max(0, bounds.width - 24), height: 18)
        let headerHeight: CGFloat = header == nil ? 0 : 28
        scrollView.frame = NSRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))
        sizeDocument()
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
        documentWidth = 0
        let digits = max(3, rows.flatMap { [$0.1, $0.2].compactMap { $0 } }.map { String($0).count }.max() ?? 3)
        func number(_ value: Int?) -> String {
            let string = value.map(String.init) ?? ""
            return String(repeating: " ", count: max(0, digits - string.count)) + string
        }
        for (line, first, second, targetID) in rows {
            let gutter = unified ? number(first) + " " + number(second) + "  " : number(first) + "  "
            let prefix: String
            switch line?.kind {
            case .addition: prefix = "+ "
            case .deletion: prefix = "− "
            default: prefix = "  "
            }
            let text = gutter + prefix + (line?.text ?? "") + "\n"
            let attributed = NSMutableAttributedString(string: text, attributes: attributes)
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                    range: NSRange(location: 0, length: (gutter as NSString).length))
            let color: NSColor?
            switch line?.kind {
            case .addition: color = NSColor.systemGreen.withAlphaComponent(0.14)
            case .deletion: color = NSColor.systemRed.withAlphaComponent(0.14)
            case .hunk:
                color = NSColor.controlAccentColor.withAlphaComponent(0.08)
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                        range: NSRange(location: 0, length: attributed.length))
            case .notice:
                color = nil
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                        range: NSRange(location: 0, length: attributed.length))
            default: color = nil
            }
            changeRanges[targetID] = NSRange(location: result.length, length: attributed.length - 1)
            result.append(attributed)
            backgrounds.append(color)
            // NSString measurement includes tab expansion through the paragraph style.
            documentWidth = max(documentWidth, attributed.size().width)
        }
        textView.textStorage?.setAttributedString(result)
        textView.rowBackgrounds = backgrounds
        documentWidth += 32
        documentHeight = CGFloat(rows.count) * DiffTextView.lineHeight + 32
        sizeDocument()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        textView.needsDisplay = true
    }

    func sizeDocument() {
        textView.setFrameSize(NSSize(width: max(documentWidth, scrollView.contentSize.width),
                                     height: max(documentHeight, scrollView.contentSize.height)))
    }

    func revealChange(_ id: Int) {
        guard let range = changeRanges[id] else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    func focusCode() { window?.makeFirstResponder(textView) }
}

@MainActor
private final class DiffTextView: NSTextView {
    static let lineHeight: CGFloat = 18
    var rowBackgrounds: [NSColor?] = []

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let first = max(0, Int((rect.minY - textContainerInset.height) / Self.lineHeight))
        let last = min(rowBackgrounds.count, Int(ceil((rect.maxY - textContainerInset.height) / Self.lineHeight)))
        guard first < last else { return }
        for index in first..<last {
            guard let color = rowBackgrounds[index] else { continue }
            color.setFill()
            NSRect(x: rect.minX, y: textContainerInset.height + CGFloat(index) * Self.lineHeight,
                   width: rect.width, height: Self.lineHeight).fill()
        }
    }
}
