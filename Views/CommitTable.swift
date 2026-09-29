import SwiftUI

struct CommitTable: View {
    let rows: [CommitRow]
    @Binding var selectedCommitID: CommitRow.ID?

    var body: some View {
        Table(rows, selection: $selectedCommitID) {
            TableColumn("Graph") { row in
                CommitGraphView(graph: row.graph)
                    .frame(height: rowHeight(for: row) + CommitTableMetrics.graphVerticalBleed * 2)
                    .offset(y: -CommitTableMetrics.graphVerticalBleed)
                    .frame(height: rowHeight(for: row), alignment: .top)
            }
            .width(min: 42, ideal: 140, max: 2_000)

            TableColumn("Commit") { row in
                CommitSummaryCell(row: row)
            }
            .width(min: 160, ideal: 680, max: 3_000)

            TableColumn("Hash") { row in
                Text(row.commit.shortHash)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 96, max: 400)

            TableColumn("Author") { row in
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.square.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                    Text(row.commit.authorName)
                        .lineLimit(1)
                }
                .font(.callout)
            }
            .width(min: 80, ideal: 170, max: 1_000)

            TableColumn("Date") { row in
                Text(DisplayFormatters.commitDate(row.commit.authoredAt))
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 178, max: 1_000)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .background(CommitTableColumnPersistence())
    }

    private func rowHeight(for row: CommitRow) -> CGFloat {
        max(CommitTableMetrics.rowHeight, CGFloat(row.graph.lines.count) * 18)
    }

}

private enum CommitTableMetrics {
    static let rowHeight: CGFloat = 42
    static let graphVerticalBleed: CGFloat = 7
}

private struct CommitSummaryCell: View {
    let row: CommitRow

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 2) {
                Text(row.commit.subject)
                    .lineLimit(1)
                    .foregroundStyle(row.commit.subject.isEmpty ? .secondary : .primary)
                HStack(spacing: 5) {
                    ForEach(row.commit.refs.filter { $0.kind != .head || !row.commit.refs.contains(where: { $0.kind == .currentBranch }) }) { badge in
                        RefBadgeView(badge: badge)
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

    var body: some View {
        HStack(spacing: 0) {
            if badge.kind == .currentBranch {
                Text("HEAD").foregroundStyle(.cyan)
                Text(" → ").foregroundStyle(.secondary)
            }
            Text(badge.kind == .tag ? "tag: \(badge.name)" : badge.name)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(style.foreground)
        .background(.thinMaterial, in: Capsule())
        .background(style.tint.opacity(0.18), in: Capsule())
        .overlay {
            Capsule()
                .stroke(style.border, lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.08), radius: 0.5, y: 0.5)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var style: RefBadgeStyle {
        switch badge.kind {
        case .head:
            return RefBadgeStyle(foreground: .cyan, tint: .cyan)
        case .currentBranch, .branch:
            return RefBadgeStyle(foreground: .green, tint: .green)
        case .remote:
            return RefBadgeStyle(foreground: .red, tint: .red)
        case .tag:
            return RefBadgeStyle(foreground: .yellow, tint: .yellow)
        }
    }
}

private struct RefBadgeStyle {
    let foreground: Color
    let tint: Color

    var border: Color {
        tint.opacity(0.42)
    }
}
