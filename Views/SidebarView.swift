import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: GitViewerStore
    let onAddRepository: () -> Void
    @AppStorage("repositorySortOrder") private var repositorySortOrderRaw = RepositorySortOrder.name.rawValue

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                ForEach(sortedRepositories) { repository in
                    RepositoryRow(repository: repository, showsUpdatedAt: repositorySortOrder == .updated)
                        .tag(repository.id)
                        .contextMenu {
                            Button("Remove Repository", role: .destructive) {
                                Task {
                                    await store.removeRepository(repository.id)
                                }
                            }
                        }
                }
            } header: {
                Text("Repositories")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarControls
        }
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

    private var sidebarControls: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 2) {
                Button(action: onAddRepository) {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Add repository")

                Button {
                    guard let selectedRepositoryID = store.selectedRepositoryID else { return }
                    Task {
                        await store.removeRepository(selectedRepositoryID)
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(store.selectedRepositoryID == nil)
                .help("Remove selected repository")

                Spacer()

                Menu {
                    Picker("Sort By", selection: repositorySortOrderBinding) {
                        ForEach(RepositorySortOrder.allCases) { sortOrder in
                            Label(sortOrder.title, systemImage: sortOrder.systemImage)
                                .tag(sortOrder)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Sort repositories")
            }
            .controlSize(.small)
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(.bar)
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
