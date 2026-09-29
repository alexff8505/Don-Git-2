import Foundation

enum GitRefParser {
    static func badges(from refs: String) -> [GitRefBadge] {
        let badges = refs.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap(badges(fromDecoratedRef:))

        return badges
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

}
