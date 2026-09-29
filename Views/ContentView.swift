import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: GitViewerStore
    @State private var isShowingCommitSheet = false
    @State private var isRefreshing = false
    @State private var repositorySelectionError: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, onAddRepository: chooseRepository)
                .frame(minWidth: 220)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            RepositoryHistoryView(store: store, onAddRepository: chooseRepository)
        }
        .navigationTitle(store.selectedRepository?.name ?? "Don Git 2")
        .navigationSubtitle(store.selectedRepository?.displayPath ?? "Local Git repositories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshHistory()
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh History", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.selectedRepository == nil || store.isLoadingHistory || store.isCommitting || isRefreshing)
                .accessibilityLabel("Refresh History")
                .help("Refresh history (⌘R)")
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingCommitSheet = true
                } label: {
                    Label("Commit…", systemImage: "square.and.pencil")
                }
                .disabled(store.selectedRepository == nil || store.localChangesCount == 0 || store.isLoadingHistory || store.isCommitting)
                .help("Commit all local changes")
                .accessibilityValue("\(store.localChangesCount) local changes")
            }
        }
        .sheet(isPresented: $isShowingCommitSheet) {
            CommitSheet(store: store, isPresented: $isShowingCommitSheet)
        }
        .alert("Unable to Add Repository", isPresented: repositorySelectionErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(repositorySelectionError ?? "An unknown error occurred.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .addRepositoryRequested)) { _ in
            chooseRepository()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshHistoryRequested)) { _ in
            refreshHistory()
        }
    }

    private var repositorySelectionErrorBinding: Binding<Bool> {
        Binding {
            repositorySelectionError != nil
        } set: { isPresented in
            if !isPresented {
                repositorySelectionError = nil
            }
        }
    }

    private func refreshHistory() {
        guard store.selectedRepository != nil, !store.isLoadingHistory, !store.isCommitting, !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            await store.refreshFromActivation()
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Add Git Repository"
        panel.message = "Choose a Git repository folder."
        panel.prompt = "Add"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                do {
                    try await store.addRepository(at: url)
                } catch {
                    repositorySelectionError = error.localizedDescription
                }
            }
        }
    }
}

private struct CommitSheet: View {
    @ObservedObject var store: GitViewerStore
    @Binding var isPresented: Bool
    @State private var message = ""
    @State private var commitError: String?
    @State private var isSubmitting = false
    @FocusState private var isMessageFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Commit Changes")
                        .font(.title2.weight(.semibold))
                    Text(store.selectedRepository?.name ?? "Repository")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit message")
                    .font(.headline)
                TextEditor(text: $message)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 100)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .focused($isMessageFocused)
                    .disabled(isSubmitting)
                    .accessibilityLabel("Commit message")
                    .accessibilityHint("Describe your changes. Press Command Return to commit.")

                Text(store.localChangesCount == 1
                     ? "1 local change will be staged and committed."
                     : "All \(store.localChangesCount.formatted()) local changes will be staged and committed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let commitError {
                Label {
                    Text(commitError)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Committing…")
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSubmitting)

                Button("Commit") {
                    guard !isSubmitting else { return }
                    isSubmitting = true
                    commitError = nil
                    Task {
                        defer { isSubmitting = false }
                        await store.commitAllChanges(message: message)
                        if let error = store.errorMessage {
                            commitError = error
                        } else {
                            isPresented = false
                        }
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .help("Commit changes (⌘Return)")
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.localChangesCount == 0 || isSubmitting || store.isCommitting)
            }
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled(isSubmitting)
        .onAppear { isMessageFocused = true }
    }
}
