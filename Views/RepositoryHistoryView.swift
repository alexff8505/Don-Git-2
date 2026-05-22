import SwiftUI

struct RepositoryHistoryView: View {
    @ObservedObject var store: GitViewerStore

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = store.errorMessage {
                ContentUnavailableView(
                    "Unable to Load History",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.selectedRepository == nil {
                ContentUnavailableView(
                    "Choose a Repository",
                    systemImage: "folder",
                    description: Text("Git repositories found in ~/Sites will appear in the sidebar.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
