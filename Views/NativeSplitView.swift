import AppKit
import SwiftUI

/// Standard AppKit splitters with stable starting sizes when detail content changes.
struct NativeSplitView<First: View, Second: View>: NSViewRepresentable {
    let isVertical: Bool
    let initialFirstSize: CGFloat
    let minimumFirstSize: CGFloat
    let minimumSecondSize: CGFloat
    var maximumFirstSize: CGFloat = .greatestFiniteMagnitude
    var persistenceKey: String? = nil
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    func makeNSView(context: Context) -> HostingSplitView {
        let view = HostingSplitView()
        view.isVertical = isVertical
        view.dividerStyle = .thin
        view.initialFirstSize = initialFirstSize
        view.minimumFirstSize = minimumFirstSize
        view.minimumSecondSize = minimumSecondSize
        view.maximumFirstSize = maximumFirstSize
        view.persistenceKey = persistenceKey
        view.update(first: AnyView(first()), second: AnyView(second()))
        return view
    }

    func updateNSView(_ view: HostingSplitView, context: Context) {
        view.update(first: AnyView(first()), second: AnyView(second()))
    }
}

@MainActor
final class HostingSplitView: NSSplitView, NSSplitViewDelegate {
    var initialFirstSize: CGFloat = 0.4
    var minimumFirstSize: CGFloat = 150
    var minimumSecondSize: CGFloat = 240
    var maximumFirstSize: CGFloat = .greatestFiniteMagnitude
    var persistenceKey: String?
    var defaults: UserDefaults = .standard
    private var adjustingSize = false
    private var firstHost: NSHostingView<AnyView>?
    private var secondHost: NSHostingView<AnyView>?
    private var hasInitialSize = false
    private var lastExtent: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(first: AnyView, second: AnyView) {
        if let firstHost, let secondHost {
            firstHost.rootView = first
            secondHost.rootView = second
        } else {
            let firstHost = NSHostingView(rootView: first)
            let secondHost = NSHostingView(rootView: second)
            // The split view owns pane geometry, rather than each changing root view's ideal size.
            firstHost.sizingOptions = []
            secondHost.sizingOptions = []
            addArrangedSubview(firstHost)
            addArrangedSubview(secondHost)
            self.firstHost = firstHost
            self.secondHost = secondHost
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let extent = isVertical ? bounds.width : bounds.height
        guard extent > 0 else { return }
        adjustingSize = true
        defer { adjustingSize = false }
        if !hasInitialSize {
            hasInitialSize = true
            let saved = persistenceKey.flatMap { defaults.object(forKey: $0) as? Double }
            let size = saved.flatMap { $0.isFinite && $0 > 0 ? CGFloat($0) : nil } ?? initialFirstSize
            let position = size <= 1 ? extent * size : size
            setPosition(clamped(position, extent: extent), ofDividerAt: 0)
        } else if lastExtent != extent, let firstHost {
            let position = isVertical ? firstHost.frame.width : firstHost.frame.height
            setPosition(clamped(position, extent: extent), ofDividerAt: 0)
        }
        lastExtent = extent
    }

    private func clamped(_ position: CGFloat, extent: CGFloat) -> CGFloat {
        let maximum = max(0, min(maximumFirstSize, extent - dividerThickness - minimumSecondSize))
        return min(maximum, max(min(minimumFirstSize, maximum), position))
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        minimumFirstSize
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let extent = isVertical ? bounds.width : bounds.height
        return min(maximumFirstSize, extent - dividerThickness - minimumSecondSize)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        let extent = isVertical ? bounds.width : bounds.height
        guard hasInitialSize, !adjustingSize, extent == lastExtent, extent > 0,
              let persistenceKey, let firstHost else { return }
        let position = isVertical ? firstHost.frame.width : firstHost.frame.height
        guard position >= minimumFirstSize else { return }
        defaults.set(Double(isVertical ? position : position / extent), forKey: persistenceKey)
    }
}
