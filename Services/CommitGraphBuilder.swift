import Foundation

struct CommitGraphBuilder {
    func rows(for commits: [GitCommit]) -> [CommitRow] {
        let commitIndexes = Dictionary(uniqueKeysWithValues: commits.enumerated().map { index, commit in
            (commit.hash, index)
        })
        var lanes: [String] = []
        var rows: [CommitRow] = []

        for commit in commits {
            var nodeLane = lanes.firstIndex(of: commit.hash)
            let hasIncomingLane = nodeLane != nil
            if nodeLane == nil {
                lanes.append(commit.hash)
                nodeLane = lanes.count - 1
            }

            guard let currentLane = nodeLane else { continue }
            let lanesBefore = lanes

            lanes.remove(at: currentLane)

            let graphParents = orderedParents(for: commit, commitIndexes: commitIndexes)
            let parentLanes = placeParents(
                graphParents,
                in: &lanes,
                startingAt: currentLane
            )
            let laneMoves = laneMoves(from: lanesBefore, to: lanes, excluding: currentLane)

            let graph = CommitGraphState(
                lanesBefore: lanesBefore,
                lanesAfter: lanes,
                laneMoves: laneMoves,
                nodeLane: currentLane,
                parentLanes: parentLanes,
                laneCount: max(lanesBefore.count, lanes.count, currentLane + 1),
                isMerge: commit.parents.count > 1,
                hasIncomingLane: hasIncomingLane
            )

            rows.append(CommitRow(commit: commit, graph: graph))
        }

        return rows
    }

    private func orderedParents(for commit: GitCommit, commitIndexes: [String: Int]) -> [String] {
        guard let firstParent = commit.parents.first,
              commit.parents.count > 2 else {
            return commit.parents
        }

        let additionalParents = commit.parents.dropFirst().sorted { lhs, rhs in
            (commitIndexes[lhs] ?? Int.max) < (commitIndexes[rhs] ?? Int.max)
        }

        return [firstParent] + additionalParents
    }

    private func placeParents(
        _ parents: [String],
        in lanes: inout [String],
        startingAt currentLane: Int
    ) -> [Int] {
        var parentLanes: [Int] = []
        var seenParents = Set<String>()

        for parent in parents where seenParents.insert(parent).inserted {
            if let existingLane = lanes.firstIndex(of: parent) {
                parentLanes.append(existingLane)
                continue
            }

            if parentLanes.isEmpty {
                let insertionLane = min(currentLane, lanes.count)
                lanes.insert(parent, at: insertionLane)
                parentLanes.append(insertionLane)
            } else {
                let insertionLane = min(currentLane + parentLanes.count, lanes.count)
                lanes.insert(parent, at: insertionLane)
                parentLanes.append(insertionLane)
            }
        }

        return parentLanes
    }

    private func laneMoves(from lanesBefore: [String], to lanesAfter: [String], excluding nodeLane: Int) -> [CommitGraphLaneMove] {
        lanesBefore.enumerated().compactMap { oldIndex, hash in
            guard oldIndex != nodeLane,
                  let newIndex = lanesAfter.firstIndex(of: hash),
                  oldIndex != newIndex else {
                return nil
            }

            return CommitGraphLaneMove(fromLane: oldIndex, toLane: newIndex)
        }
    }
}
