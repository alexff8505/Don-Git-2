import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Finder's native path control handles truncation within narrow diff panes.
struct FilePathView: NSViewRepresentable {
    let repository: GitRepository
    let file: CommitChangedFile

    func makeNSView(context: Context) -> NSPathControl {
        let control = NSPathControl()
        control.pathStyle = .standard
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        control.isEditable = false
        control.backgroundColor = .clear
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel("File path")
        return control
    }

    func updateNSView(_ control: NSPathControl, context: Context) {
        control.url = repository.path.appendingPathComponent(file.path)
        let items = Array(control.pathItems.suffix(file.path.split(separator: "/").count + 1))
        items.first?.title = repository.name
        for (index, item) in items.enumerated() {
            item.image = index == items.count - 1
                ? NSWorkspace.shared.icon(forFile: repository.path.appendingPathComponent(file.path).path)
                : NSWorkspace.shared.icon(for: .folder)
        }
        control.pathItems = items
        control.setAccessibilityValue(file.path)
    }
}
