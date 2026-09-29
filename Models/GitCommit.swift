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

    var id: String {
        "\(kind)-\(name)"
    }
}

struct CommitRow: Identifiable, Hashable, Sendable {
    let commit: GitCommit
    let graph: CommitGraphState

    var id: String {
        commit.id
    }
}

// Each line is emitted by Git's graph renderer, including merge and collapse rows.
struct CommitGraphState: Hashable, Sendable {
    let lines: [[GitGraphGlyph]]
    let hasParents: Bool
    let incomingColor: [Int]?
    let outgoingColor: [Int]?

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
