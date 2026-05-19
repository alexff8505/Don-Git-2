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

    private struct CacheKey: Hashable {
        let repositoryID: GitRepository.ID
        let layout: HistoryLayout
    }

    private struct HistoryCacheEntry {
        let signature: String
        let branch: String?
        let rows: [CommitRow]
    }

    private let gitClient = GitClient()
    private var historyCache: [CacheKey: HistoryCacheEntry] = [:]
    private var hasLoadedInitialData = false
    private var autoRefreshTask: Task<Void, Never>?
    private var isRefreshing = false
    private var historyLoadGeneration = 0

    var selectedRepository: GitRepository? {
        guard let selectedRepositoryID else { return nil }
        return repositories.first { $0.id == selectedRepositoryID }
    }

    var graphColumnWidth: CGFloat {
        let maxLaneCount = rows.map(\.graph.laneCount).max() ?? 1
        return CGFloat(min(max(maxLaneCount, 1), 8)) * 18 + 26
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
                try? await Task.sleep(for: .seconds(10))
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
        selectedCommitID = nil
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
            rows = []
            selectedCommitID = nil
            currentBranch = nil
        }

        if selectedRepositoryID == nil, selectFirstIfNeeded {
            selectedRepositoryID = found.first?.id
        }
    }

    private func reloadSelectedHistory(showsLoading: Bool = true) async {
        guard let selectedRepository else {
            historyLoadGeneration += 1
            rows = []
            selectedCommitID = nil
            currentBranch = nil
            errorMessage = repositories.isEmpty ? "No git repositories were found in ~/Sites." : nil
            return
        }

        historyLoadGeneration += 1
        let loadGeneration = historyLoadGeneration
        let repositoryID = selectedRepository.id

        if showsLoading {
            isLoadingHistory = true
        }
        errorMessage = nil

        do {
            async let signatureTask = gitClient.historySignature(repository: selectedRepository)
            async let branchTask = gitClient.currentBranch(repository: selectedRepository)
            let signature = try await signatureTask
            let branch = await branchTask
            let cacheKey = CacheKey(repositoryID: selectedRepository.id, layout: layout)

            guard isCurrentHistoryLoad(loadGeneration, repositoryID: repositoryID) else { return }

            if let cached = historyCache[cacheKey], cached.signature == signature {
                rows = cached.rows
                currentBranch = branch ?? cached.branch
                isLoadingHistory = false
                return
            }

            let loadedRows = try await gitClient.loadHistory(repository: selectedRepository, layout: layout)
            guard isCurrentHistoryLoad(loadGeneration, repositoryID: repositoryID) else { return }

            historyCache[cacheKey] = HistoryCacheEntry(signature: signature, branch: branch, rows: loadedRows)
            rows = loadedRows
            currentBranch = branch
            isLoadingHistory = false
        } catch {
            guard isCurrentHistoryLoad(loadGeneration, repositoryID: repositoryID) else { return }

            rows = []
            selectedCommitID = nil
            currentBranch = nil
            isLoadingHistory = false
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

    private func isCurrentHistoryLoad(_ generation: Int, repositoryID: GitRepository.ID) -> Bool {
        historyLoadGeneration == generation && selectedRepositoryID == repositoryID
    }
}
