import SwiftUI

struct CommitTable: View {
    let rows: [CommitRow]
    @Binding var selectedCommitID: CommitRow.ID?
    let graphColumnWidth: CGFloat

    @State private var graphWidth: CGFloat = 64
    @State private var commitWidth: CGFloat = 520
    @State private var authorWidth: CGFloat = 170
    @State private var hashWidth: CGFloat = 96
    @State private var dateWidth: CGFloat = 178

    var body: some View {
        GeometryReader { geometry in
            let resolvedCommitWidth = max(commitWidth, geometry.size.width - fixedColumnWidth)
            let tableWidth = graphWidth
                + resolvedCommitWidth
                + authorWidth
                + hashWidth
                + dateWidth
                + CommitTableMetrics.resizerWidth * CommitTableMetrics.resizerCount
            let rowsHeight = max(0, geometry.size.height - CommitTableMetrics.headerHeight - 1)

            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    header(commitWidth: resolvedCommitWidth)

                    Divider()

                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(rows.indices, id: \.self) { index in
                                let row = rows[index]
                                CommitDataRow(
                                    row: row,
                                    isFirstRow: index == 0,
                                    isSelected: selectedCommitID == row.id,
                                    isAlternate: !index.isMultiple(of: 2),
                                    graphWidth: graphWidth,
                                    commitWidth: resolvedCommitWidth,
                                    authorWidth: authorWidth,
                                    hashWidth: hashWidth,
                                    dateWidth: dateWidth
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedCommitID = row.id
                                }
                            }
                        }
                        .frame(width: tableWidth)
                    }
                    .frame(width: tableWidth, height: rowsHeight)
                    .background(Color.white)
                }
                .frame(width: tableWidth)
            }
            .background(Color.white)
        }
        .onAppear {
            graphWidth = fittedGraphWidth
        }
        .onChange(of: graphColumnWidth) { _, newValue in
            graphWidth = max(56, min(newValue, 180))
        }
    }

    private var fixedColumnWidth: CGFloat {
        graphWidth + authorWidth + hashWidth + dateWidth + CommitTableMetrics.resizerWidth * CommitTableMetrics.resizerCount
    }

    private var fittedGraphWidth: CGFloat {
        max(56, min(graphColumnWidth, 180))
    }

    private func header(commitWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HeaderCell(title: "Graph", width: graphWidth)
            ColumnResizer(width: $graphWidth, minimum: 56, maximum: 220)

            HeaderCell(title: "Commit", width: commitWidth)
            ColumnResizer(width: $commitWidth, minimum: 260, maximum: 900)

            HeaderCell(title: "Author", width: authorWidth)
            ColumnResizer(width: $authorWidth, minimum: 120, maximum: 280)

            HeaderCell(title: "Hash", width: hashWidth)
            ColumnResizer(width: $hashWidth, minimum: 78, maximum: 160)

            HeaderCell(title: "Date", width: dateWidth)
            ColumnResizer(width: $dateWidth, minimum: 140, maximum: 260)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(height: CommitTableMetrics.headerHeight)
        .background(.bar)
    }
}

private enum CommitTableMetrics {
    static let headerHeight: CGFloat = 30
    static let resizerWidth: CGFloat = 9
    static let resizerCount: CGFloat = 5
    static let rowHeight: CGFloat = 38
    static let laneSpacing: CGFloat = 18
    static let laneXInset: CGFloat = 14
    static let nodeRadius: CGFloat = 4.75
    static let lineWidth: CGFloat = 2.5
}

private struct HeaderCell: View {
    let title: String
    let width: CGFloat

    var body: some View {
        Text(title)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .padding(.leading, 10)
    }
}

private struct ColumnResizer: View {
    @Binding var width: CGFloat
    let minimum: CGFloat
    let maximum: CGFloat
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 1)
            .padding(.vertical, 6)
            .frame(width: CommitTableMetrics.resizerWidth)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        let baseWidth = dragStartWidth ?? width
                        width = min(max(baseWidth + value.translation.width, minimum), maximum)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .help("Resize column")
    }
}

private struct CommitDataRow: View {
    let row: CommitRow
    let isFirstRow: Bool
    let isSelected: Bool
    let isAlternate: Bool
    let graphWidth: CGFloat
    let commitWidth: CGFloat
    let authorWidth: CGFloat
    let hashWidth: CGFloat
    let dateWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            CommitGraphView(graph: row.graph, isFirstRow: isFirstRow)
                .frame(width: graphWidth, height: CommitTableMetrics.rowHeight)

            ColumnGutter()

            CommitSummaryCell(row: row)
                .frame(width: commitWidth, alignment: .leading)

            ColumnGutter()

            HStack(spacing: 6) {
                Image(systemName: "person.crop.square.fill")
                    .foregroundStyle(.secondary)
                Text(row.commit.authorName)
                    .lineLimit(1)
            }
            .frame(width: authorWidth, alignment: .leading)

            ColumnGutter()

            Text(row.commit.shortHash)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(width: hashWidth, alignment: .leading)

            ColumnGutter()

            Text(DisplayFormatters.commitDate(row.commit.authoredAt))
                .lineLimit(1)
                .frame(width: dateWidth, alignment: .leading)

            ColumnGutter()
        }
        .frame(height: CommitTableMetrics.rowHeight)
        .background(rowBackground)
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.28))
        }

        if isAlternate {
            return AnyShapeStyle(Color.black.opacity(0.035))
        }

        return AnyShapeStyle(Color.clear)
    }
}

private struct ColumnGutter: View {
    var body: some View {
        Color.clear
            .frame(width: CommitTableMetrics.resizerWidth)
    }
}

private struct CommitSummaryCell: View {
    let row: CommitRow

    var body: some View {
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
        .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
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
