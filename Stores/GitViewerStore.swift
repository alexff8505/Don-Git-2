import Combine
import Foundation

struct OriginRefreshState {
    var isRefreshing = false
    var lastChecked: Date?
    var hasOrigin: Bool?
    var errorMessage: String?
}

@MainActor
final class GitViewerStore: ObservableObject {
    @Published var repositories: [GitRepository] = []
    @Published var selectedRepositoryID: GitRepository.ID?
    @Published var rows: [CommitRow] = []
    @Published var selectedCommitID: CommitRow.ID? {
        didSet { rememberSelectedCommit() }
    }
    @Published var currentBranch: String?
    @Published var localChangesCount = 0
    @Published private(set) var localChangesRevision = 0
    @Published private(set) var localChangesError: String?
    @Published var isCommitting = false
    @Published var isLoadingRepositories = false
    @Published var isLoadingHistory = false
    @Published var errorMessage: String?
    @Published private(set) var repositoryFolderColors: [GitRepository.ID: RepositoryFolderColor] = [:]
    @Published private var originStates: [GitRepository.ID: OriginRefreshState] = [:]

    private struct HistoryCacheEntry {
        let signature: String
        let branch: String?
        let rows: [CommitRow]
    }

    private let gitClient = GitClient()
    private let defaults: UserDefaults
    private let repositoryPathsKey = "repositoryPaths"
    private let selectedRepositoryPathKey = "selectedRepositoryPath"
    private let selectedCommitsKey = "selectedCommitsByRepository"
    private let repositoryFolderColorsKey = "repositoryFolderColors"
    private var selectedCommits: [GitRepository.ID: CommitRow.ID] = [:]
    private var loadedHistoryRepositoryID: GitRepository.ID?
    private var historyCache: [GitRepository.ID: HistoryCacheEntry] = [:]
    private var hasLoadedInitialData = false
    private var autoRefreshTask: Task<Void, Never>?
    private var isRefreshing = false
    private var historyLoadGeneration = 0
    private var originRefreshTasks: [GitRepository.ID: Task<Bool, Error>] = [:]
    private var originLastAttempts: [GitRepository.ID: Date] = [:]

    var originRefreshState: OriginRefreshState {
        selectedRepositoryID.flatMap { originStates[$0] } ?? OriginRefreshState()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedRepositoryID = defaults.string(forKey: selectedRepositoryPathKey)
        selectedCommits = defaults.dictionary(forKey: selectedCommitsKey) as? [String: String] ?? [:]
        let savedColors = defaults.dictionary(forKey: repositoryFolderColorsKey) as? [String: String] ?? [:]
        repositoryFolderColors = savedColors.reduce(into: [:]) { result, entry in
            guard let color = RepositoryFolderColor(rawValue: entry.value), color != .defaultColor else { return }
            result[entry.key] = color
        }
    }

    var selectedRepository: GitRepository? {
        guard let selectedRepositoryID else { return nil }
        return repositories.first { $0.id == selectedRepositoryID }
    }

    var historyEntries: [HistoryEntry] {
        (localChangesCount > 0 ? [.workingTree(localChangesCount)] : []) + rows.map(HistoryEntry.commit)
    }

    var isShowingLocalChanges: Bool { selectedCommitID == HistoryEntry.workingTreeID }

    func moveCommit(_ direction: Int) {
        let entries = historyEntries
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex { $0.id == selectedCommitID } ?? (direction > 0 ? -1 : entries.count)
        selectedCommitID = entries[min(max(current + direction, 0), entries.count - 1)].id
    }

    func loadInitialData() async {
        guard !hasLoadedInitialData else { return }
        hasLoadedInitialData = true
        await refreshRepositories(selectFirstIfNeeded: true)
        await refreshSelectedHistory(forceOrigin: true)
    }

    func startAutoRefresh() {
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await self?.refreshAutomatically()
            }
        }
    }

    func selectRepository(_ id: GitRepository.ID?) async {
        guard selectedRepositoryID != id else { return }
        clearHistorySelection()
        selectedRepositoryID = id
        persistSelectedRepository()
        currentBranch = nil
        localChangesCount = 0
        localChangesError = nil
        await refreshSelectedHistory(forceOrigin: true)
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
        originStates[id] = nil
        originLastAttempts[id] = nil
        selectedCommits[id] = nil
        defaults.set(selectedCommits, forKey: selectedCommitsKey)
        repositoryFolderColors[id] = nil
        persistRepositoryFolderColors()

        guard selectedRepositoryID == id else { return }
        clearHistorySelection()
        selectedRepositoryID = repositories.first?.id
        persistSelectedRepository()
        await refreshSelectedHistory(forceOrigin: true)
    }

    func repositoryFolderColor(for id: GitRepository.ID) -> RepositoryFolderColor {
        repositoryFolderColors[id] ?? .defaultColor
    }

    func setRepositoryFolderColor(_ color: RepositoryFolderColor, for id: GitRepository.ID) {
        if color == .defaultColor {
            repositoryFolderColors[id] = nil
        } else {
            repositoryFolderColors[id] = color
        }
        persistRepositoryFolderColors()
    }

    func refreshFromActivation() async {
        guard hasLoadedInitialData else { return }
        await refreshRepositories(selectFirstIfNeeded: false, showsLoading: false)
        await refreshSelectedHistory(forceOrigin: true, showsLoading: false)
    }

    func commitAllChanges(message: String) async {
        guard let selectedRepository else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, localChangesCount > 0, localChangesError == nil, !isCommitting else { return }

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
            clearHistorySelection()
            currentBranch = nil
            localChangesCount = 0
            localChangesError = nil
        }

        if selectedRepositoryID == nil, selectFirstIfNeeded {
            selectedRepositoryID = found.first?.id
            persistSelectedRepository()
        }
    }

    private func reloadSelectedHistory(showsLoading: Bool = true) async {
        guard let selectedRepository else {
            historyLoadGeneration += 1
            clearHistorySelection()
            currentBranch = nil
            localChangesCount = 0
            localChangesError = nil
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
            var localChanges: Int?
            var changesError: String?
            do { localChanges = try await localChangesTask }
            catch { changesError = error.localizedDescription }

            guard isCurrentHistoryLoad(loadGeneration, repositoryID: repositoryID) else { return }
            if let localChanges {
                localChangesCount = localChanges
                localChangesRevision += 1
            }
            localChangesError = changesError

            if let cached = historyCache[selectedRepository.id], cached.signature == signature {
                applyHistory(cached.rows, repositoryID: repositoryID)
                currentBranch = branch ?? cached.branch
                isLoadingHistory = false
                return
            }

            let loadedRows = try await gitClient.loadHistory(repository: selectedRepository)
            guard isCurrentHistoryLoad(loadGeneration, repositoryID: repositoryID) else { return }

            historyCache[selectedRepository.id] = HistoryCacheEntry(signature: signature, branch: branch, rows: loadedRows)
            applyHistory(loadedRows, repositoryID: repositoryID)
            currentBranch = branch
            isLoadingHistory = false
        } catch {
            guard isCurrentHistoryLoad(loadGeneration, repositoryID: repositoryID) else { return }

            clearHistorySelection()
            currentBranch = nil
            localChangesCount = 0
            isLoadingHistory = false
            errorMessage = error.localizedDescription
        }
    }

    func refreshAutomatically() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let repository = selectedRepository
        await reloadSelectedHistory(showsLoading: false)
        guard let repository, selectedRepositoryID == repository.id, originRefreshTasks[repository.id] == nil else { return }
        // Network checks must not delay updates to local files.
        Task { [weak self] in
            guard let self, await self.refreshOrigin(repository, force: false),
                  self.selectedRepositoryID == repository.id else { return }
            await self.reloadSelectedHistory(showsLoading: false)
        }
    }

    private func refreshSelectedHistory(forceOrigin: Bool = false, showsLoading: Bool = true) async {
        let repository = selectedRepository
        // Display local history immediately, even when the network is slow or unavailable.
        await reloadSelectedHistory(showsLoading: showsLoading)
        guard let repository, selectedRepositoryID == repository.id else { return }
        guard await refreshOrigin(repository, force: forceOrigin) else { return }
        guard selectedRepositoryID == repository.id else { return }
        await reloadSelectedHistory(showsLoading: false)
    }

    private func refreshOrigin(_ repository: GitRepository, force: Bool) async -> Bool {
        let id = repository.id
        // Activation, manual refresh and the timer share the same fetch for a repository.
        if let pending = originRefreshTasks[id] {
            _ = try? await pending.value
            return true
        }
        if !force, let lastAttempt = originLastAttempts[id], Date().timeIntervalSince(lastAttempt) < 60 {
            return false
        }

        originLastAttempts[id] = Date()
        var state = originStates[id] ?? OriginRefreshState()
        state.isRefreshing = true
        originStates[id] = state
        let task = Task { [gitClient] in try await gitClient.fetchOrigin(repository: repository) }
        originRefreshTasks[id] = task
        do {
            state.hasOrigin = try await task.value
            state.lastChecked = state.hasOrigin == true ? Date() : nil
            state.errorMessage = nil
        } catch {
            state.errorMessage = error.localizedDescription
        }
        state.isRefreshing = false
        originRefreshTasks[id] = nil
        guard repositories.contains(where: { $0.id == id }) else { return true }
        originStates[id] = state
        return true
    }

    private func isCurrentHistoryLoad(_ generation: Int, repositoryID: GitRepository.ID) -> Bool {
        historyLoadGeneration == generation && selectedRepositoryID == repositoryID
    }

    private var configuredRepositoryPaths: [String] {
        defaults.stringArray(forKey: repositoryPathsKey) ?? []
    }

    private func rememberSelectedCommit() {
        // A table can still send selection updates while its repository is changing.
        guard let repositoryID = selectedRepositoryID,
              loadedHistoryRepositoryID == repositoryID,
              let selectedCommitID,
              historyEntries.contains(where: { $0.id == selectedCommitID }),
              selectedCommits[repositoryID] != selectedCommitID else { return }

        selectedCommits[repositoryID] = selectedCommitID
        defaults.set(selectedCommits, forKey: selectedCommitsKey)
    }

    private func clearHistorySelection() {
        loadedHistoryRepositoryID = nil
        selectedCommitID = nil
        rows = []
    }

    private func applyHistory(_ loadedRows: [CommitRow], repositoryID: GitRepository.ID) {
        let commitID = selectedCommits[repositoryID] ?? (localChangesCount > 0 ? HistoryEntry.workingTreeID : nil)
        loadedHistoryRepositoryID = nil
        if rows != loadedRows { rows = loadedRows }
        loadedHistoryRepositoryID = repositoryID
        let selection: String?
        if commitID == HistoryEntry.workingTreeID {
            selection = localChangesCount > 0 ? HistoryEntry.workingTreeID
                : (loadedRows.first { $0.commit.refs.contains { $0.kind == .head } } ?? loadedRows.first)?.id
        } else {
            selection = loadedRows.first(where: { $0.id == commitID })?.id
        }
        if selectedCommitID != selection { selectedCommitID = selection }
    }

    private func persistSelectedRepository() {
        if let selectedRepositoryID {
            defaults.set(selectedRepositoryID, forKey: selectedRepositoryPathKey)
        } else {
            defaults.removeObject(forKey: selectedRepositoryPathKey)
        }
    }

    private func persistRepositoryFolderColors() {
        defaults.set(
            repositoryFolderColors.mapValues(\.rawValue),
            forKey: repositoryFolderColorsKey
        )
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
