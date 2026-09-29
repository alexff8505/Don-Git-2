import AppKit
import SwiftUI

@main
struct DonGitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = GitViewerStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .task {
                    await store.loadInitialData()
                    store.startAutoRefresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await store.refreshFromActivation()
                    }
                }
                .frame(minWidth: 980, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1_240, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Repository…") {
                    NotificationCenter.default.post(name: .addRepositoryRequested, object: nil)
                }
                .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Button("Refresh History") {
                    NotificationCenter.default.post(name: .refreshHistoryRequested, object: nil)
                }
                .keyboardShortcut("r")
                .disabled(store.selectedRepository == nil || store.isLoadingHistory || store.isCommitting)
            }
            CommandMenu("Navigate") {
                Button("Focus Repositories") {
                    NotificationCenter.default.post(name: .focusRepositories, object: nil)
                }
                .keyboardShortcut("0")
                .disabled(store.repositories.isEmpty)
                Button("Focus Commit History") {
                    NotificationCenter.default.post(name: .focusCommitHistory, object: nil)
                }
                .keyboardShortcut("1")
                .disabled(store.rows.isEmpty || store.isLoadingHistory)
                Button("Focus Changed Files") {
                    NotificationCenter.default.post(name: .focusChangedFiles, object: nil)
                }
                .keyboardShortcut("2")
                .disabled(store.selectedCommitID == nil)
                Button("Focus Code Diff") {
                    NotificationCenter.default.post(name: .focusCodeDiff, object: nil)
                }
                .keyboardShortcut("3")
                .disabled(store.selectedCommitID == nil)
                Divider()
                Button("Previous Commit") { store.moveCommit(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .control])
                    .disabled(store.rows.isEmpty || store.isLoadingHistory)
                Button("Next Commit") { store.moveCommit(1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .control])
                    .disabled(store.rows.isEmpty || store.isLoadingHistory)
                Divider()
                Button("Previous Changed File") {
                    NotificationCenter.default.post(name: .navigateChangedFile, object: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(store.selectedCommitID == nil)
                Button("Next Changed File") {
                    NotificationCenter.default.post(name: .navigateChangedFile, object: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(store.selectedCommitID == nil)
                Divider()
                Button("Previous Change") {
                    NotificationCenter.default.post(name: .navigateDiffChange, object: -1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(store.selectedCommitID == nil)
                Button("Next Change") {
                    NotificationCenter.default.post(name: .navigateDiffChange, object: 1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(store.selectedCommitID == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            AppDelegate.disallowWindowTabs()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        Task { @MainActor in
            AppDelegate.disallowWindowTabs()
        }
    }

    @MainActor
    private static func disallowWindowTabs() {
        for window in NSApp.windows {
            window.tabbingMode = .disallowed
        }
    }
}
