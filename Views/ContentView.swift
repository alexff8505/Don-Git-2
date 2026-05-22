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
        .navigationTitle("")
        .navigationSubtitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                RepositoryTitleView(
                    title: store.selectedRepository?.name ?? "DonGit",
                    subtitle: navigationSubtitle
                )
            }

            ToolbarItemGroup {
                Picker("Layout", selection: layoutBinding) {
                    ForEach(HistoryLayout.allCases) { layout in
                        Text(layout.rawValue).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
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

private struct RepositoryTitleView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 220, alignment: .leading)
    }
}
