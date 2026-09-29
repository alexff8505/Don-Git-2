import Foundation

enum DiffPresentation: String, CaseIterable, Identifiable {
    case unified = "Unified"
    case sideBySide = "Side by Side"
    var id: String { rawValue }
}

struct CommitChangedFile: Identifiable, Hashable, Sendable {
    let path: String
    let previousPath: String?
    let status: String
    let additions: Int?
    let deletions: Int?

    var id: String { path }
    var isBinary: Bool { additions == nil || deletions == nil }
    var statusTitle: String {
        switch status.first {
        case "A": "Added"
        case "D": "Deleted"
        case "R": "Renamed"
        case "C": "Copied"
        case "T": "Type changed"
        default: "Modified"
        }
    }
}

struct CommitChanges: Sendable {
    let baseRevision: String
    let files: [CommitChangedFile]
    let message: String

    var additions: Int { files.compactMap(\.additions).reduce(0, +) }
    var deletions: Int { files.compactMap(\.deletions).reduce(0, +) }
}

struct DiffLine: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case context, addition, deletion, hunk, notice }
    let id: Int
    let kind: Kind
    let text: String
    let oldNumber: Int?
    let newNumber: Int?
}

struct SplitDiffLine: Hashable, Sendable {
    let left: DiffLine?
    let right: DiffLine?
}

struct FileDiff: Equatable, Sendable {
    let lines: [DiffLine]
    let isBinary: Bool

    /// Navigate individual changed blocks, even when Git groups several into one hunk.
    var changeIDs: [Int] {
        var result: [Int] = []
        var isChanging = false
        for line in lines {
            switch line.kind {
            case .addition, .deletion:
                if !isChanging { result.append(line.id) }
                isChanging = true
            case .notice: break
            default: isChanging = false
            }
        }
        return result
    }

    /// Pair each replacement block by row, keeping later context aligned in both panes.
    var splitLines: [SplitDiffLine] {
        var result: [SplitDiffLine] = []
        var deleted: [DiffLine] = []
        var added: [DiffLine] = []
        var deletedNotice: DiffLine?
        var addedNotice: DiffLine?
        var precedingKind: DiffLine.Kind?
        func flush() {
            for index in 0..<max(deleted.count, added.count) {
                result.append(SplitDiffLine(
                    left: index < deleted.count ? deleted[index] : nil,
                    right: index < added.count ? added[index] : nil
                ))
            }
            if deletedNotice != nil || addedNotice != nil {
                result.append(SplitDiffLine(left: deletedNotice, right: addedNotice))
            }
            deleted.removeAll(keepingCapacity: true)
            added.removeAll(keepingCapacity: true)
            deletedNotice = nil
            addedNotice = nil
        }
        for line in lines {
            switch line.kind {
            case .deletion:
                deleted.append(line)
            case .addition:
                added.append(line)
            case .notice where line.text.hasPrefix("\\ No newline") && precedingKind == .deletion:
                deletedNotice = line
            case .notice where line.text.hasPrefix("\\ No newline") && precedingKind == .addition:
                addedNotice = line
            default:
                flush()
                result.append(SplitDiffLine(left: line, right: line))
            }
            precedingKind = line.kind
        }
        flush()
        return result
    }
}
