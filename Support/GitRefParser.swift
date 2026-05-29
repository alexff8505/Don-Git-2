import Foundation

enum GitRefParser {
    static func badges(from refs: String) -> [GitRefBadge] {
        let badges = refs.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap(badges(fromDecoratedRef:))

        return orderedBadges(badges)
    }

    private static func badges(fromDecoratedRef ref: String) -> [GitRefBadge] {
        if ref.hasPrefix("HEAD -> ") {
            let branch = String(ref.dropFirst("HEAD -> ".count))
            return [
                GitRefBadge(name: "HEAD", kind: .head),
                GitRefBadge(name: branch, kind: .currentBranch)
            ]
        }

        if ref == "HEAD" {
            return [GitRefBadge(name: "HEAD", kind: .head)]
        }

        if ref.hasPrefix("tag: ") {
            return [GitRefBadge(name: String(ref.dropFirst("tag: ".count)), kind: .tag)]
        }

        if ref.hasPrefix("origin/") {
            return [GitRefBadge(name: ref, kind: .remote)]
        }

        return [GitRefBadge(name: ref, kind: .branch)]
    }

    private static func orderedBadges(_ badges: [GitRefBadge]) -> [GitRefBadge] {
        let heads = badges.filter { $0.kind == .head }
        let headRemotes = badges.filter { $0.kind == .remote && $0.name == "origin/HEAD" }
        let locals = badges.filter { $0.kind == .currentBranch || $0.kind == .branch }
        let remotes = badges.filter { $0.kind == .remote && $0.name != "origin/HEAD" }
        let tags = badges.filter { $0.kind == .tag }
        var usedRemoteIDs = Set<GitRefBadge.ID>()

        var ordered = heads
        ordered.append(contentsOf: headRemotes)

        for local in locals {
            ordered.append(local)

            for remote in remotes where remote.localName == local.name {
                ordered.append(remote)
                usedRemoteIDs.insert(remote.id)
            }
        }

        ordered.append(contentsOf: remotes.filter { !usedRemoteIDs.contains($0.id) })
        ordered.append(contentsOf: tags)

        return ordered
    }
}

private extension GitRefBadge {
    var localName: String {
        guard kind == .remote, let slashIndex = name.firstIndex(of: "/") else {
            return name
        }

        return String(name[name.index(after: slashIndex)...])
    }
}
