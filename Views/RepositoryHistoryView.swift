import SwiftUI

struct RepositoryHistoryView: View {
    @ObservedObject var store: GitViewerStore
    let onAddRepository: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = store.errorMessage {
                ContentUnavailableView(
                    "Unable to Load History",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.repositories.isEmpty {
                ContentUnavailableView {
                    Label("No Repositories", systemImage: "folder.badge.plus")
                } description: {
                    Text("Add a Git repository to view its commit history.")
                } actions: {
                    Button("Add Repository…", action: onAddRepository)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.selectedRepository == nil {
                ContentUnavailableView(
                    "Choose a Repository",
                    systemImage: "folder",
                    description: Text("Select a repository in the sidebar to view its commit history.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.rows.isEmpty && store.isLoadingHistory {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CommitTable(
                    rows: store.rows,
                    selectedCommitID: $store.selectedCommitID
                )
            }
        }
    }
}
