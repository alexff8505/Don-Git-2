import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: GitViewerStore
    @State private var isShowingCommitSheet = false
    @State private var repositorySelectionError: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, onAddRepository: chooseRepository)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            RepositoryHistoryView(store: store, onAddRepository: chooseRepository)
        }
        .navigationTitle(store.selectedRepository?.name ?? "DonGit")
        .navigationSubtitle(store.selectedRepository == nil ? "Add a Git repository to begin" : "")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                RepositoryStatusView(store: store)
                    .padding(.leading, 8)

                Button {
                    isShowingCommitSheet = true
                } label: {
                    CommitStatusIcon(localChangesCount: store.localChangesCount)
                }
                .disabled(store.selectedRepository == nil || store.localChangesCount == 0 || store.isCommitting)
                .help("Commit all local changes")
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

private struct RepositoryStatusView: View {
    @ObservedObject var store: GitViewerStore

    var body: some View {
        if store.selectedRepository != nil {
            HStack(spacing: 10) {
                if let branch {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .imageScale(.small)
                        Text(branch)
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                }

                Text("\(store.rows.count.formatted()) commits")
                Text("Local Changes: (\(store.localChangesCount.formatted()))")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var branch: String? {
        guard store.currentBranch?.isEmpty == false else { return nil }
        return store.currentBranch
    }
}

private struct CommitStatusIcon: View {
    let localChangesCount: Int

    var body: some View {
        Label {
            Text("Commit")
        } icon: {
            Image(systemName: "checkmark.circle")
                .imageScale(.large)
                .frame(width: 24, height: 22)
                .overlay(alignment: .topTrailing) {
                    if localChangesCount > 0 {
                        Text(badgeText)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .padding(.horizontal, localChangesCount < 10 ? 0 : 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(.red, in: Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
        }
        .accessibilityValue("\(localChangesCount) local changes")
    }

    private var badgeText: String {
        localChangesCount > 99 ? "99+" : localChangesCount.formatted()
    }
}

private struct CommitSheet: View {
    @ObservedObject var store: GitViewerStore
    @Binding var isPresented: Bool
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Commit All Local Changes")
                .font(.headline)

            TextField("Commit message", text: $message)
                .textFieldStyle(.roundedBorder)

            Text("\(store.localChangesCount.formatted()) local changes will be staged and committed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Commit") {
                    Task {
                        await store.commitAllChanges(message: message)
                        if store.errorMessage == nil {
                            isPresented = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isCommitting)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
