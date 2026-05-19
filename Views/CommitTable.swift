import SwiftUI

struct CommitTable: View {
    let rows: [CommitRow]
    @Binding var selectedCommitID: CommitRow.ID?
    let graphColumnWidth: CGFloat

    var body: some View {
        Table(rows, selection: $selectedCommitID) {
            TableColumn("Commit") { row in
                CommitSummaryCell(row: row, graphColumnWidth: graphColumnWidth)
            }
            .width(min: 420, ideal: 640)

            TableColumn("Author") { row in
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.square.fill")
                        .foregroundStyle(.blue)
                    Text(row.commit.authorName)
                        .lineLimit(1)
                }
            }
            .width(min: 130, ideal: 170, max: 240)

            TableColumn("Hash") { row in
                Text(row.commit.shortHash)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
            }
            .width(min: 82, ideal: 92, max: 110)

            TableColumn("Date") { row in
                Text(DisplayFormatters.commitDate(row.commit.authoredAt))
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 170, max: 220)
        }
        .alternatingRowBackgrounds(.enabled)
    }
}

private struct CommitSummaryCell: View {
    let row: CommitRow
    let graphColumnWidth: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            CommitGraphView(graph: row.graph)
                .frame(width: graphColumnWidth, height: 28)

            HStack(spacing: 5) {
                ForEach(row.commit.refs.prefix(4)) { badge in
                    RefBadgeView(badge: badge)
                }

                Text(row.commit.subject)
                    .lineLimit(1)
                    .foregroundStyle(row.commit.subject.isEmpty ? .secondary : .primary)
            }
        }
    }
}

private struct RefBadgeView: View {
    let badge: GitRefBadge

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(badge.name)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(border, lineWidth: 1)
        }
    }

    private var systemImage: String {
        switch badge.kind {
        case .head:
            "scope"
        case .currentBranch, .branch:
            "checkmark"
        case .remote:
            "network"
        case .tag:
            "tag"
        }
    }

    private var foreground: Color {
        switch badge.kind {
        case .head:
            .secondary
        case .currentBranch:
            .primary
        case .branch:
            .orange
        case .remote:
            .red
        case .tag:
            .purple
        }
    }

    private var background: Color {
        switch badge.kind {
        case .head:
            Color.secondary.opacity(0.08)
        case .currentBranch, .branch:
            Color.orange.opacity(0.12)
        case .remote:
            Color.red.opacity(0.10)
        case .tag:
            Color.purple.opacity(0.10)
        }
    }

    private var border: Color {
        foreground.opacity(0.45)
    }
}
