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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
