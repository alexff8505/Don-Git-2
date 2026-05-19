import Combine
import Foundation

@MainActor
final class GitViewerStore: ObservableObject {
    @Published var repositories: [GitRepository] = []
    @Published var selectedRepositoryID: GitRepository.ID?
    @Published var rows: [CommitRow] = []
    @Published var selectedCommitID: CommitRow.ID?
    @Published var layout: HistoryLayout = .topological
    @Published var currentBranch: String?
    @Published var isLoadingRepositories = false
    @Published var isLoadingHistory = false
    @Published var errorMessage: String?

    private let scanner = GitRepositoryScanner()
    private let gitClient = GitClient()
    private var hasLoadedInitialData = false
    private var autoRefreshTask: Task<Void, Never>?
    private var isRefreshing = false

    var selectedRepository: GitRepository? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    var graphColumnWidth: CGFloat {
        let maxLaneCount = rows.map(\.graph.laneCount).max() ?? 1
        return CGFloat(min(max(maxLaneCount, 1), 12)) * 18 + 22
    }

    func loadInitialData() async {
        guard !hasLoadedInitialData else { return }
        hasLoadedInitialData = true
        await refreshRepositories(selectFirstIfNeeded: true)
        await reloadSelectedHistory()
    }

    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await self?.refreshSilently()
            }
        }
    }

    func selectRepository(_ id: GitRepository.ID?) async {
        guard selectedRepositoryID != id else { return }
        selectedRepositoryID = id
        selectedCommitID = nil
        await reloadSelectedHistory()
    }

    func setLayout(_ newLayout: HistoryLayout) async {
        guard layout != newLayout else { return }
        layout = newLayout
        await reloadSelectedHistory()
    }

    func refreshFromActivation() async {
        guard hasLoadedInitialData else { return }
        await refreshSilently()
    }

    private func refreshRepositories(selectFirstIfNeeded: Bool, showsLoading: Bool = true) async {
        if showsLoading {
            isLoadingRepositories = true
        }
        defer {
            if showsLoading {
                isLoadingRepositories = false
            }
        }

        let found = await Task.detached(priority: .userInitiated) {
            GitRepositoryScanner().repositories()
        }.value

        repositories = found

        if let selectedRepositoryID, !found.contains(where: { $0.id == selectedRepositoryID }) {
            self.selectedRepositoryID = nil
        }

        if selectedRepositoryID == nil, selectFirstIfNeeded {
            selectedRepositoryID = found.first?.id
        }
    }

    private func reloadSelectedHistory(showsLoading: Bool = true) async {
        guard let selectedRepository else {
            rows = []
            currentBranch = nil
            errorMessage = repositories.isEmpty ? "No git repositories were found in ~/Sites." : nil
            return
        }

        if showsLoading {
            isLoadingHistory = true
        }
        errorMessage = nil
        defer {
            if showsLoading {
                isLoadingHistory = false
            }
        }

        do {
            async let history = gitClient.loadHistory(repository: selectedRepository, layout: layout)
            async let branch = gitClient.currentBranch(repository: selectedRepository)
            rows = try await history
            currentBranch = await branch
        } catch {
            rows = []
            currentBranch = nil
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSilently() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await refreshRepositories(selectFirstIfNeeded: false, showsLoading: false)
        await reloadSelectedHistory(showsLoading: false)
    }
}
