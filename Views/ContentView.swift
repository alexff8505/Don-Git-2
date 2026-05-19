import SwiftUI

struct ContentView: View {
    @ObservedObject var store: GitViewerStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            RepositoryHistoryView(store: store)
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Layout", selection: layoutBinding) {
                    ForEach(HistoryLayout.allCases) { layout in
                        Text(layout.rawValue).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
    }

    private var layoutBinding: Binding<HistoryLayout> {
        Binding {
            store.layout
        } set: { newLayout in
            Task {
                await store.setLayout(newLayout)
            }
        }
    }
}
