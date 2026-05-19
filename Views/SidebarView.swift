import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: GitViewerStore

    var body: some View {
        List(selection: selectionBinding) {
            Section("Repositories") {
                ForEach(store.repositories) { repository in
                    RepositoryRow(repository: repository)
                        .tag(repository.id)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .overlay {
            if store.isLoadingRepositories && store.repositories.isEmpty {
                ProgressView()
            }
        }
    }

    private var selectionBinding: Binding<GitRepository.ID?> {
        Binding {
            store.selectedRepositoryID
        } set: { id in
            Task {
                await store.selectRepository(id)
            }
        }
    }
}

private struct RepositoryRow: View {
    let repository: GitRepository

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .lineLimit(1)
                Text(repository.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
        }
    }
}
