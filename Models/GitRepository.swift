import Foundation

struct GitRepository: Identifiable, Hashable, Sendable {
    let path: URL

    var id: String {
        path.path
    }

    var name: String {
        path.lastPathComponent
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.path.hasPrefix(home) {
            return "~" + path.path.dropFirst(home.count)
        }
        return path.path
    }
}
