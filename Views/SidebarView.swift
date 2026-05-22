import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: GitViewerStore
    @AppStorage("repositorySortOrder") private var repositorySortOrderRaw = RepositorySortOrder.name.rawValue

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                ForEach(sortedRepositories) { repository in
                    RepositoryRow(repository: repository, showsUpdatedAt: repositorySortOrder == .updated)
                        .tag(repository.id)
                }
            } header: {
                HStack {
                    Text("Repositories")

                    Spacer()

                    Menu {
                        Picker("Sort Repositories", selection: repositorySortOrderBinding) {
                            ForEach(RepositorySortOrder.allCases) { sortOrder in
                                Label(sortOrder.title, systemImage: sortOrder.systemImage)
                                    .tag(sortOrder)
                            }
                        }
                    } label: {
                        Label("Sort Repositories", systemImage: repositorySortOrder.systemImage)
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .help("Sort repositories")
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.isLoadingRepositories && store.repositories.isEmpty {
                ProgressView()
            }
        }
    }

    private var sortedRepositories: [GitRepository] {
        switch repositorySortOrder {
        case .name:
            store.repositories.sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        case .updated:
            store.repositories.sorted { lhs, rhs in
                switch (lhs.updatedAt, rhs.updatedAt) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
        }
    }

    private var repositorySortOrder: RepositorySortOrder {
        RepositorySortOrder(rawValue: repositorySortOrderRaw) ?? .name
    }

    private var repositorySortOrderBinding: Binding<RepositorySortOrder> {
        Binding {
            repositorySortOrder
        } set: { newValue in
            repositorySortOrderRaw = newValue.rawValue
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

private enum RepositorySortOrder: String, CaseIterable, Identifiable {
    case name
    case updated

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .name:
            "Name"
        case .updated:
            "Date Updated"
        }
    }

    var systemImage: String {
        switch self {
        case .name:
            "textformat"
        case .updated:
            "clock"
        }
    }
}

private struct RepositoryRow: View {
    let repository: GitRepository
    let showsUpdatedAt: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(repository.name)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        guard showsUpdatedAt, let updatedAt = repository.updatedAt else {
            return repository.displayPath
        }

        return "\(DisplayFormatters.repositoryUpdatedDate(updatedAt))  \(repository.displayPath)"
    }
}
