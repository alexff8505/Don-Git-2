import SwiftUI

struct CommitChangesView: View {
    let repository: GitRepository
    let commit: GitCommit
    @StateObject private var details = CommitChangesStore()
    @State private var parentIndex = 0
    @State private var showsMessage = false
    @FocusState private var filesHaveKeyboardFocus: Bool
    @AppStorage("commitDiffPresentation") private var presentation: DiffPresentation = .unified
    @AppStorage("commitDiffWordWrap") private var wordWrap = false

    private var parent: String? { commit.parents.indices.contains(parentIndex) ? commit.parents[parentIndex] : nil }
    private var comparisonID: String { repository.id + ":" + commit.hash + ":" + (parent ?? "root") }
    private var fileID: String { comparisonID + ":" + (details.changes?.baseRevision ?? "") + ":" + (details.selectedFileID ?? "") }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if details.isLoading {
                ProgressView("Loading changes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = details.error {
                ContentUnavailableView {
                    Label("Unable to Load Changes", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error).textSelection(.enabled)
                } actions: {
                    Button("Try Again") {
                        Task { await details.load(repository: repository, commit: commit, parent: parent) }
                    }
                }
            } else if details.changes?.files.isEmpty == true {
                ContentUnavailableView("No File Changes", systemImage: "doc", description:
                    Text(commit.parents.count > 1 ? "This merge has no file changes compared with the selected parent." : "This commit has no file changes."))
            } else {
                NativeSplitView(isVertical: true, initialFirstSize: 270, minimumFirstSize: 180, minimumSecondSize: 300, maximumFirstSize: 460, persistenceKey: "changedFilesPaneWidth") {
                    fileList
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } second: {
                    diffPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(.background)
        .task(id: comparisonID) { await details.load(repository: repository, commit: commit, parent: parent) }
        .task(id: fileID) { await details.loadDiff(repository: repository, commit: commit) }
        .onReceive(NotificationCenter.default.publisher(for: .navigateChangedFile)) { notification in
            if let direction = notification.object as? Int { details.moveFile(direction) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateDiffChange)) { notification in
            if let direction = notification.object as? Int { details.moveChange(direction) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.subject.isEmpty ? "Untitled commit" : commit.subject)
                        .font(.headline)
                        .lineLimit(1)
                        .textSelection(.enabled)
                        .help(commit.subject)
                    HStack(spacing: 6) {
                        Text(commit.shortHash).monospaced()
                            .help(commit.hash)
                        Text("·")
                        Text(commit.authorName).lineLimit(1)
                        Text("·")
                        Text(DisplayFormatters.commitDate(commit.authoredAt)).lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Picker("Diff View", selection: $presentation) {
                    ForEach(DiffPresentation.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
                .help("Choose unified or side-by-side changes")
            }
            HStack(spacing: 10) {
                if let changes = details.changes {
                    Text("\(changes.files.count) \(changes.files.count == 1 ? "file" : "files") changed")
                        .foregroundStyle(.secondary)
                    Text("+\(changes.additions)").foregroundStyle(.green)
                    Text("−\(changes.deletions)").foregroundStyle(.red)
                }
                Spacer(minLength: 0)
                if commit.parents.count > 1 {
                    Picker("Compare with", selection: $parentIndex) {
                        ForEach(commit.parents.indices, id: \.self) { index in
                            Text("Parent \(index + 1) (\(commit.parents[index].prefix(7)))").tag(index)
                        }
                    }
                    .fixedSize()
                    .help("Choose the parent to compare this merge against")
                } else {
                    Text(parent == nil ? "Empty tree → \(commit.shortHash)" : "Parent → \(commit.shortHash)")
                        .foregroundStyle(.secondary)
                }
                Button {
                    showsMessage.toggle()
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .help("Show full commit message")
                .accessibilityLabel("Show full commit message")
                .popover(isPresented: $showsMessage) {
                    ScrollView {
                        Text(details.changes?.message ?? commit.subject)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(width: 420, height: 240)
                }
            }
            .font(.caption)
            .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var fileList: some View {
        ScrollViewReader { proxy in
            List(selection: $details.selectedFileID) {
                ForEach(details.changes?.files ?? []) { file in
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.path).lineLimit(1).truncationMode(.middle)
                            if let previous = file.previousPath {
                                Text("From \(previous)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 0)
                        if file.isBinary {
                            Text("Binary").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 5) {
                                Text("+\(file.additions ?? 0)").foregroundStyle(.green)
                                Text("−\(file.deletions ?? 0)").foregroundStyle(.red)
                            }
                            .font(.caption2)
                            .monospacedDigit()
                        }
                        Text(String(file.status.prefix(1)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(file.id)
                    .help(file.path + " — " + file.statusTitle)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(file.path + ", " + file.statusTitle)
                }
            }
            .listStyle(.inset)
            .accessibilityLabel("Changed files")
            .focused($filesHaveKeyboardFocus)
            .simultaneousGesture(TapGesture().onEnded {
                filesHaveKeyboardFocus = true
            })
            .onReceive(NotificationCenter.default.publisher(for: .focusChangedFiles)) { _ in
                filesHaveKeyboardFocus = true
            }
            .onChange(of: details.selectedFileID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private var diffPane: some View {
        VStack(spacing: 0) {
            if let file = details.selectedFile {
                fileToolbar(file)
                Divider()
            }
            if details.isLoadingDiff {
                ProgressView("Loading diff…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = details.diffError {
                ContentUnavailableView {
                    Label("Unable to Load Diff", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error).textSelection(.enabled)
                } actions: {
                    Button("Try Again") { Task { await details.loadDiff(repository: repository, commit: commit) } }
                }
            } else if let diff = details.diff {
                if diff.isBinary || details.selectedFile?.isBinary == true {
                    ContentUnavailableView("Binary File", systemImage: "doc", description: Text("A text diff is unavailable for this file."))
                } else if diff.lines.isEmpty {
                    ContentUnavailableView("No Text Changes", systemImage: "doc", description: Text("Only the file name or metadata changed."))
                } else {
                    DiffCodeView(diff: diff, presentation: presentation, selectedChangeID: details.selectedChangeID, wordWrap: wordWrap)
                }
            } else {
                ContentUnavailableView("Select a File", systemImage: "doc.text.magnifyingglass", description: Text("Choose a changed file to view its diff."))
            }
        }
    }

    private func fileToolbar(_ file: CommitChangedFile) -> some View {
        let changes = details.diff?.changeIDs ?? []
        let selectedIndex = details.selectedChangeID.flatMap { changes.firstIndex(of: $0) }
        return VStack(spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "doc").foregroundStyle(.secondary)
                Text((file.path as NSString).lastPathComponent)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path + " — " + file.statusTitle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Toggle("Wrap Lines", isOn: $wordWrap)
                    .toggleStyle(.button)
                    .help("Wrap long code lines to fit the pane")
                    .disabled(file.isBinary)
                if file.isBinary {
                    Text("Binary").foregroundStyle(.secondary)
                } else {
                    Text("+\(file.additions ?? 0)").foregroundStyle(.green)
                    Text("−\(file.deletions ?? 0)").foregroundStyle(.red)
                }
                ControlGroup {
                    Button { details.moveChange(-1) } label: { Image(systemName: "chevron.up") }
                        .help("Previous change (⌥⌘←)")
                        .accessibilityLabel("Previous change")
                        .disabled(changes.isEmpty || selectedIndex == 0)
                    Button { details.moveChange(1) } label: { Image(systemName: "chevron.down") }
                        .help("Next change (⌥⌘→)")
                        .accessibilityLabel("Next change")
                        .disabled(changes.isEmpty || selectedIndex == changes.count - 1)
                }
                .fixedSize()
                Text(selectedIndex.map { "\($0 + 1) of \(changes.count)" }
                     ?? "\(changes.count) \(changes.count == 1 ? "change" : "changes")")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityLabel(selectedIndex.map { "Change \($0 + 1) of \(changes.count)" }
                                        ?? "\(changes.count) \(changes.count == 1 ? "change" : "changes")")
            }
            .font(.callout)
            FilePathView(repository: repository, file: file)
                .frame(height: 22)
                .help(file.path)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}
