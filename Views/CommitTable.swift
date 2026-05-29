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
            .width(min: 260, ideal: 680, max: 1_600)

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
        GeometryReader { proxy in
            HStack(spacing: 5) {
                ForEach(row.commit.refs) { badge in
                    RefBadgeView(badge: badge)
                }

                Text(row.commit.subject)
                    .lineLimit(1)
                    .foregroundStyle(row.commit.subject.isEmpty ? .secondary : .primary)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .clipped()
        }
    }
}

private struct RefBadgeView: View {
    let badge: GitRefBadge

    var body: some View {
        HStack(spacing: 0) {
            Text(badge.name)
                .lineLimit(1)
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 4)
        .padding(.vertical, 1.5)
        .foregroundStyle(style.foreground)
        .background(style.background, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(style.border, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var style: RefBadgeStyle {
        let name = badge.name.lowercased()

        switch badge.kind {
        case .head:
            return RefBadgeStyle(
                foreground: .white,
                background: Color(red: 0.70, green: 0.29, blue: 0.02),
                border: Color(red: 1.00, green: 0.49, blue: 0.08)
            )
        case .remote:
            if name == "origin/head" {
                return RefBadgeStyle(
                    foreground: .white,
                    background: Color(red: 0.76, green: 0.34, blue: 0.04),
                    border: Color(red: 1.00, green: 0.56, blue: 0.13)
                )
            }

            return RefBadgeStyle(
                foreground: Color(red: 0.94, green: 0.91, blue: 1.00),
                background: Color(red: 0.17, green: 0.10, blue: 0.42),
                border: Color(red: 0.55, green: 0.36, blue: 1.00)
            )
        case .currentBranch:
            return RefBadgeStyle(
                foreground: Color(red: 0.86, green: 1.00, blue: 0.94),
                background: Color(red: 0.00, green: 0.42, blue: 0.33),
                border: Color(red: 0.00, green: 0.86, blue: 0.65)
            )
        case .branch:
            if name == "dev" {
                return RefBadgeStyle(
                    foreground: Color(red: 0.86, green: 1.00, blue: 0.94),
                    background: Color(red: 0.00, green: 0.42, blue: 0.33),
                    border: Color(red: 0.00, green: 0.86, blue: 0.65)
                )
            }

            if name == "main" {
                return RefBadgeStyle(
                    foreground: Color(red: 0.86, green: 1.00, blue: 0.94),
                    background: Color(red: 0.00, green: 0.42, blue: 0.33),
                    border: Color(red: 0.00, green: 0.86, blue: 0.65)
                )
            }

            return RefBadgeStyle(
                foreground: Color(red: 0.86, green: 1.00, blue: 0.94),
                background: Color(red: 0.00, green: 0.42, blue: 0.33),
                border: Color(red: 0.00, green: 0.86, blue: 0.65)
            )
        case .tag:
            return RefBadgeStyle(
                foreground: Color(red: 0.94, green: 0.91, blue: 1.00),
                background: Color(red: 0.17, green: 0.10, blue: 0.42),
                border: Color(red: 0.55, green: 0.36, blue: 1.00)
            )
        }
    }
}

private struct RefBadgeStyle {
    let foreground: Color
    let background: Color
    let border: Color
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
