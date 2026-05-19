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

struct CommitGraphState: Hashable, Sendable {
    let lanesBefore: [String]
    let lanesAfter: [String]
    let nodeLane: Int
    let parentLanes: [Int]
    let laneCount: Int
    let isMerge: Bool
}

enum HistoryLayout: String, CaseIterable, Identifiable, Sendable {
    case topological = "Topological"
    case date = "Date"

    var id: Self {
        self
    }

    var gitOrderingArguments: [String] {
        switch self {
        case .topological:
            return ["--topo-order"]
        case .date:
            return ["--date-order"]
        }
    }
}
