import Combine
import Foundation

@MainActor
final class CommitChangesStore: ObservableObject {
    @Published private(set) var changes: CommitChanges?
    @Published private(set) var diff: FileDiff?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingDiff = false
    @Published private(set) var error: String?
    @Published private(set) var diffError: String?
    @Published var selectedFileID: String?
    @Published var selectedChangeID: Int?

    private let client = GitClient()
    private var generation = 0
    private var diffGeneration = 0

    var selectedFile: CommitChangedFile? { changes?.files.first { $0.id == selectedFileID } }

    func load(repository: GitRepository, commit: GitCommit, parent: String?) async {
        generation += 1
        diffGeneration += 1
        let request = generation
        changes = nil
        diff = nil
        error = nil
        diffError = nil
        selectedFileID = nil
        selectedChangeID = nil
        isLoading = true
        isLoadingDiff = false
        do {
            let result = try await client.loadChanges(repository: repository, commit: commit, parent: parent)
            guard request == generation, !Task.isCancelled else { return }
            changes = result
            selectedFileID = result.files.first?.id
            isLoading = false
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func loadDiff(repository: GitRepository, commit: GitCommit) async {
        diffGeneration += 1
        let request = diffGeneration
        let changesRequest = generation
        diff = nil
        diffError = nil
        selectedChangeID = nil
        guard let changes, let file = selectedFile else {
            isLoadingDiff = false
            return
        }
        isLoadingDiff = true
        do {
            let result = try await client.loadDiff(repository: repository, commit: commit, base: changes.baseRevision, file: file)
            guard request == diffGeneration, changesRequest == generation, !Task.isCancelled else { return }
            diff = result
            isLoadingDiff = false
        } catch {
            guard request == diffGeneration, changesRequest == generation, !Task.isCancelled else { return }
            diffError = error.localizedDescription
            isLoadingDiff = false
        }
    }

    func moveFile(_ direction: Int) {
        guard let files = changes?.files, !files.isEmpty else { return }
        let current = files.firstIndex { $0.id == selectedFileID } ?? (direction > 0 ? -1 : files.count)
        selectedFileID = files[min(max(current + direction, 0), files.count - 1)].id
    }

    func moveChange(_ direction: Int) {
        let changes = diff?.changeIDs ?? []
        guard !changes.isEmpty else { return }
        let current = changes.firstIndex { $0 == selectedChangeID } ?? (direction > 0 ? -1 : changes.count)
        selectedChangeID = changes[min(max(current + direction, 0), changes.count - 1)]
    }
}
