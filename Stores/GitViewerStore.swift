import Combine
import Foundation

@MainActor
final class GitViewerStore: ObservableObject {
    @Published var repositories: [GitRepository] = []
    @Published var selectedRepositoryID: GitRepository.ID?
    @Published var rows: [CommitRow] = []
    @Published var selectedCommitID: CommitRow.ID?
    @Published var currentBranch: String?
    @Published var localChangesCount = 0
    @Published var isCommitting = false
    @Published var isLoadingRepositories = false
    @Published var isLoadingHistory = false
    @Published var errorMessage: String?

    private struct HistoryCacheEntry {
        let signature: String
        let branch: String?
        let rows: [CommitRow]
    }

    private let gitClient = GitClient()
    private let defaults: UserDefaults
    private let repositoryPathsKey = "repositoryPaths"
    private let selectedRepositoryPathKey = "selectedRepositoryPath"
    private var historyCache: [GitRepository.ID: HistoryCacheEntry] = [:]
    private var hasLoadedInitialData = false
    private var autoRefreshTask: Task<Void, Never>?
    private var isRefreshing = false
    private var historyLoadGeneration = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedRepositoryID = defaults.string(forKey: selectedRepositoryPathKey)
    }

    var selectedRepository: GitRepository? {
        guard let selectedRepositoryID else { return nil }
        return repositories.first { $0.id == selectedRepositoryID }
    }

    var graphColumnWidth: CGFloat {
        let maxLaneCount = rows.map(\.graph.laneCount).max() ?? 1
        return CGFloat(min(max(maxLaneCount, 1), 10)) * 14 + 22
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
        persistSelectedRepository()
        selectedCommitID = nil
        await reloadSelectedHistory()
    }

    func addRepository(at selectedURL: URL) async throws {
        let selectedPath = selectedURL.path
        let repository = await Task.detached(priority: .userInitiated) {
            GitRepositoryScanner().repository(at: URL(fileURLWithPath: selectedPath))
        }.value

        guard let repository else {
            throw RepositorySelectionError.notGitRepository
        }

        var paths = configuredRepositoryPaths
        if !paths.contains(repository.id) {
            paths.append(repository.id)
            defaults.set(paths, forKey: repositoryPathsKey)
        }

        if let index = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories[index] = repository
        } else {
            repositories.append(repository)
        }

        await selectRepository(repository.id)
    }

    func removeRepository(_ id: GitRepository.ID) async {
        let paths = configuredRepositoryPaths.filter { $0 != id }
        defaults.set(paths, forKey: repositoryPathsKey)
        repositories.removeAll { $0.id == id }
        historyCache[id] = nil

        guard selectedRepositoryID == id else { return }
        selectedRepositoryID = repositories.first?.id
        persistSelectedRepository()
        selectedCommitID = nil
        await reloadSelectedHistory()
    }

    func refreshFromActivation() async {
        guard hasLoadedInitialData else { return }
        await refreshSilently()
    }

    func commitAllChanges(message: String) async {
        guard let selectedRepository else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, localChangesCount > 0, !isCommitting else { return }

        isCommitting = true
        errorMessage = nil
        do {
            try await gitClient.commitAllChanges(repository: selectedRepository, message: trimmedMessage)
            historyCache[selectedRepository.id] = nil
            await reloadSelectedHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCommitting = false
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

        let paths = configuredRepositoryPaths
        let found = await Task.detached(priority: .userInitiated) {
            GitRepositoryScanner().repositories(at: paths)
        }.value

        repositories = found

        if let selectedRepositoryID, !found.contains(where: { $0.id == selectedRepositoryID }) {
            self.selectedRepositoryID = nil
            persistSelectedRepository()
            rows = []
            selectedCommitID = nil
            currentBranch = nil
            localChangesCount = 0
        }

        if selectedRepositoryID == nil, selectFirstIfNeeded {
            selectedRepositoryID = found.first?.id
            persistSelectedRepository()
        }
    }

    private func reloadSelectedHistory(showsLoading: Bool = true) async {
        guard let selectedRepository else {
            historyLoadGeneration += 1
            rows = []
            selectedCommitID = nil
            currentBranch = nil
            localChangesCount = 0
            isLoadingHistory = false
            errorMessage = nil
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
            async let localChangesTask = gitClient.localChangesCount(repository: selectedRepository)
            let signature = try await signatureTask
            let branch = await branchTask
            let localChanges = (try? await localChangesTask) ?? 0

            guard isCurrentHistoryLoad(loadGeneration, repositoryID: repositoryID) else { return }
            localChangesCount = localChanges

            if let cached = historyCache[selectedRepository.id], cached.signature == signature {
                rows = cached.rows
                currentBranch = branch ?? cached.branch
                isLoadingHistory = false
                return
            }

            let loadedRows = try await gitClient.loadHistory(repository: selectedRepository)
            guard isCurrentHistoryLoad(loadGeneration, repositoryID: repositoryID) else { return }

            historyCache[selectedRepository.id] = HistoryCacheEntry(signature: signature, branch: branch, rows: loadedRows)
            rows = loadedRows
            currentBranch = branch
            isLoadingHistory = false
        } catch {
            guard isCurrentHistoryLoad(loadGeneration, repositoryID: repositoryID) else { return }

            rows = []
            selectedCommitID = nil
            currentBranch = nil
            localChangesCount = 0
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

    private var configuredRepositoryPaths: [String] {
        defaults.stringArray(forKey: repositoryPathsKey) ?? []
    }

    private func persistSelectedRepository() {
        if let selectedRepositoryID {
            defaults.set(selectedRepositoryID, forKey: selectedRepositoryPathKey)
        } else {
            defaults.removeObject(forKey: selectedRepositoryPathKey)
        }
    }
}

enum RepositorySelectionError: LocalizedError {
    case notGitRepository

    var errorDescription: String? {
        switch self {
        case .notGitRepository:
            "The selected folder is not inside a Git repository."
        }
    }
}
