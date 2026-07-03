import Foundation

struct CommitGraphBuilder {
    func rows(for commits: [GitCommit]) -> [CommitRow] {
        let commitIndexes = Dictionary(uniqueKeysWithValues: commits.enumerated().map { index, commit in
            (commit.hash, index)
        })
        var lanes: [GraphLane] = []
        var rows: [CommitRow] = []

        for commit in commits {
            var nodeLane = lanes.firstIndex { $0.hash == commit.hash }
            let hasIncomingLane = nodeLane != nil
            if nodeLane == nil {
                lanes.append(GraphLane(hash: commit.hash, colorIndex: nextColorIndex(for: lanes)))
                nodeLane = lanes.count - 1
            }

            guard let currentLane = nodeLane else { continue }
            let lanesBefore = lanes
            let nodeColorIndex = lanesBefore[currentLane].colorIndex

            lanes.remove(at: currentLane)

            let graphParents = orderedParents(for: commit, commitIndexes: commitIndexes)
            let parents = placeParents(
                graphParents,
                in: &lanes,
                startingAt: currentLane,
                continuingColorIndex: nodeColorIndex
            )
            let laneMoves = laneMoves(from: lanesBefore, to: lanes, excluding: currentLane)

            let graph = CommitGraphState(
                lanesBefore: lanesBefore.map(\.hash),
                lanesAfter: lanes.map(\.hash),
                laneColorIndexesBefore: lanesBefore.map(\.colorIndex),
                laneColorIndexesAfter: lanes.map(\.colorIndex),
                laneMoves: laneMoves,
                nodeLane: currentLane,
                nodeColorIndex: nodeColorIndex,
                parentLanes: parents.map(\.lane),
                parentConnectorColorIndexes: parents.map(\.connectorColorIndex),
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
        in lanes: inout [GraphLane],
        startingAt currentLane: Int,
        continuingColorIndex: Int
    ) -> [GraphParentLane] {
        var parentLanes: [GraphParentLane] = []
        var seenParents = Set<String>()

        for parent in parents where seenParents.insert(parent).inserted {
            let isFirstParent = parentLanes.isEmpty

            if let existingLane = lanes.firstIndex(where: { $0.hash == parent }) {
                parentLanes.append(GraphParentLane(lane: existingLane, connectorColorIndex: lanes[existingLane].colorIndex))
                continue
            }

            if isFirstParent {
                let insertionLane = min(currentLane, lanes.count)
                lanes.insert(GraphLane(hash: parent, colorIndex: continuingColorIndex), at: insertionLane)
                parentLanes.append(GraphParentLane(lane: insertionLane, connectorColorIndex: continuingColorIndex))
            } else {
                let insertionLane = min(currentLane + parentLanes.count, lanes.count)
                let colorIndex = nextColorIndex(for: lanes, avoiding: [continuingColorIndex])
                lanes.insert(GraphLane(hash: parent, colorIndex: colorIndex), at: insertionLane)
                parentLanes.append(GraphParentLane(lane: insertionLane, connectorColorIndex: colorIndex))
            }
        }

        return parentLanes
    }

    private func laneMoves(from lanesBefore: [GraphLane], to lanesAfter: [GraphLane], excluding nodeLane: Int) -> [CommitGraphLaneMove] {
        lanesBefore.enumerated().compactMap { oldIndex, hash in
            guard oldIndex != nodeLane,
                  let newIndex = lanesAfter.firstIndex(where: { $0.hash == hash.hash }),
                  oldIndex != newIndex else {
                return nil
            }

            return CommitGraphLaneMove(fromLane: oldIndex, toLane: newIndex, colorIndex: hash.colorIndex)
        }
    }

    private func nextColorIndex(for lanes: [GraphLane], avoiding reservedColorIndexes: Set<Int> = []) -> Int {
        let usedColorIndexes = Set(lanes.map(\.colorIndex)).union(reservedColorIndexes)
        var colorIndex = 0

        while usedColorIndexes.contains(colorIndex) {
            colorIndex += 1
        }

        return colorIndex
    }
}

private struct GraphLane {
    let hash: String
    let colorIndex: Int
}

private struct GraphParentLane {
    let lane: Int
    let connectorColorIndex: Int
}
