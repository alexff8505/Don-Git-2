import SwiftUI

struct CommitTable: View {
    let rows: [CommitRow]
    var localChangesCount = 0
    @Binding var selectedCommitID: CommitRow.ID?
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        return Table(entries, selection: $selectedCommitID) {
            TableColumn("Graph") { row in
                // The graph is drawn above the native table in one shared layer.
                // Cells provide sizing and accessibility, never clipped lane fragments.
                Color.clear
                    .frame(height: rowHeight(for: row))
                    .accessibilityLabel(row.commitRow?.graph.accessibilityDescription
                                        ?? "Uncommitted working tree, based on HEAD")
                    .help("Follow parent connections from top to bottom. Drag the Graph column divider to see more lanes.")
            }
            .width(min: 42, ideal: 96, max: max(2_000, graphWidth + 16))

            TableColumn("Commit") { row in
                if let commit = row.commitRow {
                    CommitSummaryCell(row: commit)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Uncommitted Changes").fontWeight(.medium)
                        Text("\(localChangesCount) \(localChangesCount == 1 ? "file" : "files") · Not committed")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .help("Review staged edits, unstaged edits, and new files compared with HEAD")
                    .accessibilityLabel("Uncommitted Changes, \(localChangesCount) files, not committed")
                }
            }
            .width(min: 160, ideal: 420, max: 3_000)

            TableColumn("Hash") { row in
                if let commit = row.commitRow?.commit {
                    Text(commit.shortHash)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                }
            }
            .width(min: 60, ideal: 96, max: 400)

            TableColumn("Author") { row in
                if let commit = row.commitRow?.commit {
                    HStack(spacing: 6) {
                        Image(systemName: "person")
                            .foregroundStyle(.secondary)
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Text(commit.authorName)
                            .lineLimit(1)
                    }
                    .font(.callout)
                }
            }
            .width(min: 80, ideal: 140, max: 1_000)

            TableColumn("Date") { row in
                if let commit = row.commitRow?.commit {
                    Text(DisplayFormatters.commitDate(commit.authoredAt)).lineLimit(1)
                }
            }
            .width(min: 100, ideal: 164, max: 1_000)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .background(CommitTableColumnPersistence(selectedRowIndex: entries.firstIndex { $0.id == selectedCommitID }))
        .background(CommitGraphOverlay(rows: rows, hasLocalChanges: localChangesCount > 0))
        .focused($hasKeyboardFocus)
        .simultaneousGesture(TapGesture().onEnded {
            hasKeyboardFocus = true
        })
        .onReceive(NotificationCenter.default.publisher(for: .focusCommitHistory)) { _ in
            hasKeyboardFocus = true
        }
    }

    private var entries: [HistoryEntry] {
        (localChangesCount > 0 ? [.workingTree(localChangesCount)] : []) + rows.map(HistoryEntry.commit)
    }

    private func rowHeight(for row: HistoryEntry) -> CGFloat {
        max(CommitTableMetrics.rowHeight, CGFloat(row.commitRow?.graph.lines.count ?? 1) * 18)
    }

    private var graphWidth: CGFloat {
        max(42, CGFloat(rows.map(\.graph.laneCount).max() ?? 1) * 16 + 12)
    }

}

private enum CommitTableMetrics {
    static let rowHeight: CGFloat = 42
}

private struct CommitSummaryCell: View {
    let row: CommitRow

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 2) {
                Text(row.commit.subject.isEmpty ? "Untitled commit" : row.commit.subject)
                    .lineLimit(1)
                    .foregroundStyle(row.commit.subject.isEmpty ? .secondary : .primary)
                HStack(spacing: 10) {
                    ForEach(GitRefParser.groups(for: row.commit.refs)) { group in
                        HStack(spacing: 5) {
                            ForEach(group.badges) { badge in
                                RefBadgeView(badge: badge)
                            }
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipped()
        }
        .help(([row.commit.subject] + row.commit.refs.map(\.name)).joined(separator: "\n"))
    }
}

private struct RefBadgeView: View {
    let badge: GitRefBadge
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        capsule
            .help(badge.checkout.map { "\(badge.name)\n\($0.help)" } ?? badge.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
    }

    private var capsule: some View {
        HStack(spacing: 0) {
            if badge.kind == .currentBranch {
                Text("HEAD")
                Text(" → ").foregroundStyle(.secondary)
            }
            Text(badge.kind == .tag ? "tag: \(badge.name)" : badge.name)
                .lineLimit(1)
            if let checkout = badge.checkout {
                Image(systemName: checkout.isMain ? "house" : "folder")
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(.primary)
        .background(tint.opacity(colorScheme == .dark ? 0.22 : 0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(contrast == .increased ? 0.6 : colorScheme == .dark ? 0.35 : 0.25),
                        lineWidth: 0.75)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var accessibilityDescription: String {
        let name = badge.kind == .currentBranch ? "HEAD, \(badge.name)" : badge.name
        guard let checkout = badge.checkout else { return name }
        return "\(name), \(checkout.label), \(checkout.path)"
    }

    private var tint: Color {
        switch badge.kind {
        case .head:
            .cyan
        case .currentBranch, .branch:
            Color(nsColor: .systemGreen)
        case .remote:
            Color(nsColor: .systemRed)
        case .tag:
            .yellow
        }
    }
}
