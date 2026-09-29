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
                        .buttonStyle(.borderedProminent)
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
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.rows.isEmpty {
                ContentUnavailableView(
                    "No Commits Yet",
                    systemImage: "clock",
                    description: Text("Commits will appear here after the first commit in this repository.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NativeSplitView(isVertical: false, initialFirstSize: 0.4, minimumFirstSize: 150, minimumSecondSize: 240) {
                    CommitTable(rows: store.rows, selectedCommitID: $store.selectedCommitID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } second: {
                    if let repository = store.selectedRepository,
                       let commit = store.rows.first(where: { $0.id == store.selectedCommitID })?.commit {
                        CommitChangesView(repository: repository, commit: commit)
                            .id(repository.id + ":" + commit.hash)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("Select a Commit", systemImage: "doc.text.magnifyingglass",
                                               description: Text("Choose a commit to view its changed files and code."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.selectedRepository != nil {
                RepositoryStatusBar(store: store)
            }
        }
    }
}

private struct RepositoryStatusBar: View {
    @ObservedObject var store: GitViewerStore

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                if store.isLoadingHistory {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Loading history…")
                } else if store.errorMessage != nil {
                    Label("History unavailable", systemImage: "exclamationmark.triangle")
                } else {
                    Label(store.currentBranch ?? "Detached HEAD", systemImage: "arrow.triangle.branch")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(store.currentBranch ?? "The repository is not on a branch")
                    Text("\(store.rows.count.formatted()) \(store.rows.count == 1 ? "commit" : "commits")")
                        .monospacedDigit()
                        .fixedSize()
                }

                Spacer(minLength: 12)

                if !store.isLoadingHistory && store.errorMessage == nil {
                    Label {
                        Text(store.localChangesCount == 0 ? "Working tree clean" : "\(store.localChangesCount.formatted()) local \(store.localChangesCount == 1 ? "change" : "changes")")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: store.localChangesCount == 0 ? "checkmark.circle" : "pencil.circle")
                    }
                    .fixedSize()
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.bar)
        }
    }
}
