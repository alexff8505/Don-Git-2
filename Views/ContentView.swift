import SwiftUI

struct ContentView: View {
    @ObservedObject var store: GitViewerStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            RepositoryHistoryView(store: store)
        }
        .navigationTitle(store.selectedRepository?.name ?? "DonGit")
        .navigationSubtitle(navigationSubtitle)
    }

    private var navigationSubtitle: String {
        guard store.selectedRepository != nil else {
            return "Git repositories in ~/Sites"
        }

        let branch = store.currentBranch?.isEmpty == false ? store.currentBranch : nil
        let count = "\(store.rows.count.formatted()) commits"
        let localChanges = "Local Changes: (\(store.localChangesCount.formatted()))"
        return [branch, count, localChanges].compactMap { $0 }.joined(separator: "  ")
    }
}
