import SwiftUI

struct CommitTable: View {
    let rows: [CommitRow]
    @Binding var selectedCommitID: CommitRow.ID?
    let graphColumnWidth: CGFloat

    var body: some View {
        Table(rows, selection: $selectedCommitID) {
            TableColumn("Graph") { row in
                CommitGraphView(graph: row.graph, isFirstRow: row.id == rows.first?.id)
                    .frame(height: CommitTableMetrics.rowHeight + CommitTableMetrics.graphVerticalBleed * 2)
                    .offset(y: -CommitTableMetrics.graphVerticalBleed)
                    .frame(height: CommitTableMetrics.rowHeight, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 2)
            }
            .width(
                min: CommitTableMetrics.minimumGraphWidth,
                ideal: fittedGraphWidth,
                max: CommitTableMetrics.maximumGraphWidth
            )

            TableColumn("Commit") { row in
                CommitSummaryCell(row: row)
            }
            .width(min: 260, ideal: 520, max: 900)

            TableColumn("Hash") { row in
                Text(row.commit.shortHash)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
            }
            .width(min: 78, ideal: 96, max: 160)

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
            .width(min: 120, ideal: 170, max: 280)

            TableColumn("Date") { row in
                Text(DisplayFormatters.commitDate(row.commit.authoredAt))
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 178, max: 260)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var fittedGraphWidth: CGFloat {
        max(CommitTableMetrics.minimumGraphWidth, min(graphColumnWidth, CommitTableMetrics.maximumGraphWidth))
    }
}

private enum CommitTableMetrics {
    static let rowHeight: CGFloat = 30
    static let minimumGraphWidth: CGFloat = 58
    static let maximumGraphWidth: CGFloat = 220
    static let graphVerticalBleed: CGFloat = 5
}

private struct CommitSummaryCell: View {
    let row: CommitRow

    var body: some View {
        HStack(spacing: 5) {
            ForEach(visibleBadges) { badge in
                RefBadgeView(
                    badge: badge,
                    localBranchColor: row.graph.color(forCommitHash: row.commit.hash)
                )
            }

            Text(row.commit.subject)
                .lineLimit(1)
                .foregroundStyle(row.commit.subject.isEmpty ? .secondary : .primary)
        }
    }

    private var visibleBadges: [GitRefBadge] {
        let baseLimit = 4
        var visible = Array(row.commit.refs.prefix(baseLimit))

        guard let nextBadge = row.commit.refs.dropFirst(baseLimit).first,
              nextBadge.kind == .remote,
              let lastLocalBadge = visible.last(where: { $0.kind == .currentBranch || $0.kind == .branch }),
              nextBadge.remoteLocalName == lastLocalBadge.name else {
            return visible
        }

        visible.append(nextBadge)
        return visible
    }
}

private struct RefBadgeView: View {
    let badge: GitRefBadge
    let localBranchColor: Color
    @Environment(\.colorScheme) private var colorScheme

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
        .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(border, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
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
            .green
        case .remote:
            remoteForeground
        case .currentBranch, .branch:
            localBranchColor
        case .tag:
            .purple
        }
    }

    private var background: Color {
        switch badge.kind {
        case .head:
            Color.green.opacity(0.12)
        case .remote:
            remoteForeground.opacity(colorScheme == .dark ? 0.20 : 0.14)
        case .currentBranch, .branch:
            localBranchColor.opacity(0.12)
        case .tag:
            Color.purple.opacity(0.10)
        }
    }

    private var border: Color {
        switch badge.kind {
        case .head:
            Color.green.opacity(0.55)
        case .remote:
            remoteForeground.opacity(colorScheme == .dark ? 0.72 : 0.50)
        case .currentBranch, .branch:
            localBranchColor.opacity(0.55)
        case .tag:
            Color.purple.opacity(0.45)
        }
    }

    private var remoteForeground: Color {
        colorScheme == .dark
            ? Color(red: 1.00, green: 0.70, blue: 0.22)
            : Color(red: 0.58, green: 0.36, blue: 0.02)
    }
}

private extension CommitGraphState {
    func color(forCommitHash hash: String) -> Color {
        if let lane = lanesBefore.firstIndex(of: hash) {
            return GitGraphColorPalette.color(for: lane)
        }

        return GitGraphColorPalette.color(for: nodeLane)
    }
}

private extension GitRefBadge {
    var remoteLocalName: String {
        guard kind == .remote, let slashIndex = name.firstIndex(of: "/") else {
            return name
        }

        return String(name[name.index(after: slashIndex)...])
    }
}
