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
                .containerBackground(.ultraThinMaterial, for: .window)
                .frame(minWidth: 980, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Repository…") {
                    NotificationCenter.default.post(name: .addRepositoryRequested, object: nil)
                }
                .keyboardShortcut("o")
            }
        }
    }
}

extension Notification.Name {
    static let addRepositoryRequested = Notification.Name("addRepositoryRequested")
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
