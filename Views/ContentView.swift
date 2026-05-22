import SwiftUI

struct ContentView: View {
    @ObservedObject var store: GitViewerStore
    @State private var isShowingCommitSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            RepositoryHistoryView(store: store)
        }
        .navigationTitle(store.selectedRepository?.name ?? "DonGit")
        .navigationSubtitle(navigationSubtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
    }

    private var navigationSubtitle: String {
        guard store.selectedRepository != nil else {
            return "Git repositories in ~/Sites"
        }

        let branch = store.currentBranch?.isEmpty == false ? store.currentBranch : nil
        let count = "\(store.rows.count.formatted()) commits"
        let localChanges = "Local Changes: (\(store.localChangesCount.formatted()))"
        return [branch, count, localChanges].compactMap { $0 }.joined(separator: "  ")
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
