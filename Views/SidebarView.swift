import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: GitViewerStore
    let onAddRepository: () -> Void
    @FocusState private var hasKeyboardFocus: Bool
    @AppStorage("repositorySortOrder") private var repositorySortOrderRaw = RepositorySortOrder.name.rawValue

    var body: some View {
        List(selection: selectionBinding) {
            Section {
                ForEach(sortedRepositories) { repository in
                    RepositoryRow(
                        repository: repository,
                        showsUpdatedAt: repositorySortOrder == .updated,
                        folderColor: store.repositoryFolderColor(for: repository.id)
                    )
                        .tag(repository.id)
                        .contextMenu {
                            Picker(
                                "Folder Colour",
                                selection: repositoryFolderColorBinding(for: repository.id)
                            ) {
                                ForEach(RepositoryFolderColor.allCases) { color in
                                    Label {
                                        Text(color.title)
                                    } icon: {
                                        FolderColorSwatch(color: color)
                                    }
                                    .tag(color)
                                }
                            }

                            Divider()

                            Button("Remove from Sidebar") {
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
        .focused($hasKeyboardFocus)
        .simultaneousGesture(TapGesture().onEnded {
            hasKeyboardFocus = true
        })
        .onReceive(NotificationCenter.default.publisher(for: .focusRepositories)) { _ in
            hasKeyboardFocus = true
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarControls
        }
        .onDeleteCommand(perform: removeSelectedRepository)
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

    private func repositoryFolderColorBinding(for id: GitRepository.ID) -> Binding<RepositoryFolderColor> {
        Binding {
            store.repositoryFolderColor(for: id)
        } set: { color in
            store.setRepositoryFolderColor(color, for: id)
        }
    }

    private var sidebarControls: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 2) {
                Button(action: onAddRepository) {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add Repository")
                .help("Add repository (⌘O)")

                Button {
                    removeSelectedRepository()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(store.selectedRepositoryID == nil)
                .accessibilityLabel("Remove from Sidebar")
                .help("Remove selected repository from the sidebar")

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
            .padding(.horizontal, 10)
            .frame(height: 44)
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

    private func removeSelectedRepository() {
        guard let selectedRepositoryID = store.selectedRepositoryID else { return }
        Task {
            await store.removeRepository(selectedRepositoryID)
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
    let folderColor: RepositoryFolderColor

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(repository.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "folder.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(folderColor.color ?? .secondary)
        }
        .padding(.vertical, 4)
        .help(repository.path.path)
        .accessibilityValue("\(repository.displayPath). Folder colour: \(folderColor.title)")
    }

    private var detail: String {
        guard showsUpdatedAt, let updatedAt = repository.updatedAt else {
            return repository.displayPath
        }

        return DisplayFormatters.repositoryUpdatedDate(updatedAt)
    }
}

private struct FolderColorSwatch: View {
    let color: RepositoryFolderColor

    var body: some View {
        if let swatch = color.color {
            Circle()
                .fill(swatch)
                .frame(width: 9, height: 9)
        } else {
            Circle()
                .stroke(.secondary, lineWidth: 1)
                .frame(width: 9, height: 9)
        }
    }
}
