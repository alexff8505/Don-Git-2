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
            } else if store.historyEntries.isEmpty && store.isLoadingHistory {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.historyEntries.isEmpty {
                ContentUnavailableView(
                    "No Commits Yet",
                    systemImage: "clock",
                    description: Text("Commits will appear here after the first commit in this repository.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NativeSplitView(isVertical: false, initialFirstSize: 0.4, minimumFirstSize: 150, minimumSecondSize: 240, persistenceKey: "commitHistoryPaneFraction") {
                    CommitTable(rows: store.rows, localChangesCount: store.localChangesCount, selectedCommitID: $store.selectedCommitID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } second: {
                    if let repository = store.selectedRepository, store.isShowingLocalChanges {
                        CommitChangesView(repository: repository, commit: nil, localChangesRevision: store.localChangesRevision)
                            .id(repository.id + ":working-tree")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let repository = store.selectedRepository,
                       let commit = store.rows.first(where: { $0.id == store.selectedCommitID })?.commit {
                        CommitChangesView(repository: repository, commit: commit)
                            .id(repository.id + ":" + commit.hash)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("Select Changes or a Commit", systemImage: "doc.text.magnifyingglass",
                                               description: Text("Choose uncommitted changes or a commit to view its changed files and code."))
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

                originStatus

                if let error = store.localChangesError {
                    Label("Local changes unavailable", systemImage: "exclamationmark.triangle")
                        .help(error)
                } else if !store.isLoadingHistory && store.errorMessage == nil {
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

    @ViewBuilder
    private var originStatus: some View {
        let state = store.originRefreshState
        Group {
            if state.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Checking origin…")
                }
            } else if let error = state.errorMessage {
                Label("Origin unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("\(error)\n\(lastCheckedDescription(state.lastChecked))\nShowing previously fetched remote branches. Press ⌘R to retry.")
                    .accessibilityHint(error + ". " + lastCheckedDescription(state.lastChecked))
            } else if state.hasOrigin == false {
                Label("No origin remote", systemImage: "network")
            } else if let checkedAt = state.lastChecked {
                Label {
                    Text("Origin checked \(checkedAt, style: .time)")
                } icon: {
                    Image(systemName: "network")
                }
                .help("\(lastCheckedDescription(checkedAt))\nChecks origin every minute and when returning to the app. Press ⌘R to check now.")
            } else {
                Label("Origin not checked", systemImage: "network")
            }
        }
        .fixedSize()
    }

    private func lastCheckedDescription(_ date: Date?) -> String {
        guard let date else { return "Origin has not been checked successfully." }
        return "Last successful check: \(date.formatted(date: .abbreviated, time: .standard))."
    }
}
