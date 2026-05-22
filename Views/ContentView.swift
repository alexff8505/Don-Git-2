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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Layout", selection: layoutBinding) {
                    ForEach(HistoryLayout.allCases) { layout in
                        Text(layout.rawValue).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 188)
                .disabled(store.selectedRepositoryID == nil)
            }
        }
    }

    private var navigationSubtitle: String {
        guard store.selectedRepository != nil else {
            return "Git repositories in ~/Sites"
        }

        let branch = store.currentBranch?.isEmpty == false ? store.currentBranch : nil
        let count = "\(store.rows.count.formatted()) commits"
        return [branch, count].compactMap { $0 }.joined(separator: "  ")
    }

    private var layoutBinding: Binding<HistoryLayout> {
        Binding {
            store.layout
        } set: { newLayout in
            Task {
                await store.setLayout(newLayout)
            }
        }
    }
}
