import Foundation

struct GitCommit: Identifiable, Hashable, Sendable {
    let hash: String
    let parents: [String]
    let authorName: String
    let authorEmail: String
    let authoredAt: Date
    let subject: String
    let refs: [GitRefBadge]

    var id: String {
        hash
    }

    var shortHash: String {
        String(hash.prefix(7))
    }
}

struct GitRefBadge: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case head
        case currentBranch
        case branch
        case remote
        case tag
    }

    let name: String
    let kind: Kind
    var checkout: GitBranchCheckout? = nil

    var id: String {
        "\(kind)-\(name)"
    }
}

struct GitRefBadgeGroup: Identifiable {
    let badges: [GitRefBadge]

    var id: String { badges[0].id }
}

struct GitBranchCheckout: Hashable, Sendable {
    let path: String
    let isMain: Bool

    var label: String { isMain ? "Main checkout" : "Worktree" }

    var help: String {
        "\(isMain ? "Main checkout" : "Linked worktree")\n\(path)"
    }
}

struct CommitRow: Identifiable, Hashable, Sendable {
    let commit: GitCommit
    let graph: CommitGraphState

    var id: String {
        commit.id
    }
}

/// A working tree is selectable alongside commits, without pretending to be one.
enum HistoryEntry: Identifiable {
    static let workingTreeID = "working-tree"
    case workingTree(Int)
    case commit(CommitRow)

    var id: String {
        switch self {
        case .workingTree: Self.workingTreeID
        case .commit(let row): row.id
        }
    }

    var commitRow: CommitRow? {
        if case .commit(let row) = self { return row }
        return nil
    }
}

// Each line is emitted by Git's graph renderer, including merge and collapse rows.
struct CommitGraphState: Hashable, Sendable {
    let lines: [[GitGraphGlyph]]
    let previousLine: [GitGraphGlyph]
    let nextLine: [GitGraphGlyph]
    let parentCount: Int
    let incomingColor: [Int]?
    let outgoingColor: [Int]?
    var pathSegments: [GitGraphSegment]? = nil
    var displayNodeColor: [Int]? = nil

    var nodeColor: [Int] { displayNodeColor ?? incomingColor ?? outgoingColor ?? [34] }

    var accessibilityDescription: String {
        let kind = parentCount == 0 ? "Root commit" : parentCount > 1 ? "Merge commit, \(parentCount) parents" : "Commit, 1 parent"
        let column = lines[nodeLine].firstIndex { $0.character == "*" } ?? 0
        return "\(kind), lane \(column / 2 + 1) of \(laneCount)"
    }

    var laneCount: Int {
        ((lines.map(\.count).max() ?? 1) + 1) / 2
    }

    var nodeLine: Int {
        lines.firstIndex { $0.contains { $0.character == "*" } } ?? 0
    }
}

struct GitGraphGlyph: Hashable, Sendable {
    let character: Character
    let color: [Int]
}

struct GitGraphPoint: Hashable, Sendable {
    let column: Double
    let line: Double
}

struct GitGraphSegment: Hashable, Sendable {
    let start: GitGraphPoint
    let end: GitGraphPoint
    let color: [Int]
}
