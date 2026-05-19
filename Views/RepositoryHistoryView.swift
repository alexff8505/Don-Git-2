import SwiftUI

struct RepositoryHistoryView: View {
    @ObservedObject var store: GitViewerStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                repository: store.selectedRepository,
                branch: store.currentBranch,
                commitCount: store.rows.count,
                isLoading: store.isLoadingHistory
            )

            Divider()

            if let errorMessage = store.errorMessage {
                ContentUnavailableView(
                    "Unable to Load History",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if store.selectedRepository == nil {
                ContentUnavailableView(
                    "Choose a Repository",
                    systemImage: "folder",
                    description: Text("Git repositories found in ~/Sites will appear in the sidebar.")
                )
            } else if store.rows.isEmpty && store.isLoadingHistory {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CommitTable(
                    rows: store.rows,
                    selectedCommitID: $store.selectedCommitID,
                    graphColumnWidth: store.graphColumnWidth
                )
            }
        }
    }
}

private struct HeaderView: View {
    let repository: GitRepository?
    let branch: String?
    let commitCount: Int
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(repository?.name ?? "Git History")
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let branch, !branch.isEmpty {
                        Label(branch, systemImage: "point.3.connected.trianglepath.dotted")
                    }

                    Text("\(commitCount.formatted()) commits")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
