import Foundation

enum GitRefParser {
    /// Group only refs on this commit; a remote at another commit is never implied.
    static func groups(for badges: [GitRefBadge]) -> [GitRefBadgeGroup] {
        let locals = badges.filter { $0.kind == .currentBranch || $0.kind == .branch }.sorted {
            if ($0.kind == .currentBranch) != ($1.kind == .currentBranch) { return $0.kind == .currentBranch }
            return $0.name < $1.name
        }
        var used: Set<String> = []
        var result: [GitRefBadgeGroup] = []
        for local in locals {
            let remotes = badges.filter {
                $0.kind == .remote && $0.name.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) == local.name
            }.sorted {
                if $0.name.hasPrefix("origin/") != $1.name.hasPrefix("origin/") { return $0.name.hasPrefix("origin/") }
                return $0.name < $1.name
            }
            let pair = [local] + remotes
            used.formUnion(pair.map(\.id))
            result.append(GitRefBadgeGroup(badges: pair))
        }
        let remaining = badges.filter {
            !used.contains($0.id) && !($0.kind == .head && locals.contains { $0.kind == .currentBranch })
        }
        let detachedHead = remaining.filter { $0.kind == .head }.map { GitRefBadgeGroup(badges: [$0]) }
        return detachedHead + result + remaining.filter { $0.kind != .head }.map { GitRefBadgeGroup(badges: [$0]) }
    }

    static func badges(from refs: String) -> [GitRefBadge] {
        let badges = refs.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap(badges(fromDecoratedRef:))

        return badges
    }

    private static func badges(fromDecoratedRef ref: String) -> [GitRefBadge] {
        if ref.hasPrefix("HEAD -> ") {
            let branch = localBranchName(String(ref.dropFirst("HEAD -> ".count)))
            return [
                GitRefBadge(name: "HEAD", kind: .head),
                GitRefBadge(name: branch, kind: .currentBranch)
            ]
        }

        if ref == "HEAD" {
            return [GitRefBadge(name: "HEAD", kind: .head)]
        }

        if ref.hasPrefix("tag: ") {
            let name = String(ref.dropFirst("tag: ".count))
            return [GitRefBadge(name: name.hasPrefix("refs/tags/") ? String(name.dropFirst(10)) : name, kind: .tag)]
        }

        if ref.hasPrefix("refs/heads/") {
            return [GitRefBadge(name: localBranchName(ref), kind: .branch)]
        }

        if ref.hasPrefix("refs/remotes/") {
            return [GitRefBadge(name: String(ref.dropFirst(13)), kind: .remote)]
        }

        if ref.hasPrefix("origin/") {
            return [GitRefBadge(name: ref, kind: .remote)]
        }

        return [GitRefBadge(name: ref, kind: .branch)]
    }

    private static func localBranchName(_ ref: String) -> String {
        ref.hasPrefix("refs/heads/") ? String(ref.dropFirst(11)) : ref
    }
}

enum GitWorktreeParser {
    /// NUL-delimited porcelain preserves paths containing spaces, newlines or quoting characters.
    /// Git always lists the main checkout (or bare repository) first, even from a linked worktree.
    static func checkouts(from output: String) -> [String: GitBranchCheckout] {
        var result: [String: GitBranchCheckout] = [:]
        var path: String?
        var branch: String?
        var isPrunable = false
        var isMain = true

        for field in output.split(separator: "\0", omittingEmptySubsequences: false) {
            if field.isEmpty {
                if let path {
                    if let branch, !isPrunable {
                        result[branch] = GitBranchCheckout(path: path, isMain: isMain)
                    }
                    isMain = false
                }
                path = nil
                branch = nil
                isPrunable = false
            } else if field.hasPrefix("worktree ") {
                path = String(field.dropFirst(9))
            } else if field.hasPrefix("branch refs/heads/") {
                branch = String(field.dropFirst(18))
            } else if field == "prunable" || field.hasPrefix("prunable ") {
                isPrunable = true
            }
        }
        return result
    }
}
