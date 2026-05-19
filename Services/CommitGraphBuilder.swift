import Foundation

struct CommitGraphBuilder {
    func rows(for commits: [GitCommit]) -> [CommitRow] {
        var lanes: [String] = []
        var rows: [CommitRow] = []

        for commit in commits {
            var nodeLane = lanes.firstIndex(of: commit.hash)
            if nodeLane == nil {
                lanes.append(commit.hash)
                nodeLane = lanes.count - 1
            }

            guard let currentLane = nodeLane else { continue }
            let lanesBefore = lanes

            if commit.parents.isEmpty {
                lanes.remove(at: currentLane)
            } else {
                lanes[currentLane] = commit.parents[0]

                for parent in commit.parents.dropFirst() where !lanes.contains(parent) {
                    lanes.append(parent)
                }
            }

            let parentLanes = commit.parents.compactMap { parent in
                lanes.firstIndex(of: parent)
            }

            let graph = CommitGraphState(
                lanesBefore: lanesBefore,
                lanesAfter: lanes,
                nodeLane: currentLane,
                parentLanes: parentLanes,
                laneCount: max(lanesBefore.count, lanes.count, currentLane + 1),
                isMerge: commit.parents.count > 1
            )

            rows.append(CommitRow(commit: commit, graph: graph))
        }

        return rows
    }
}
