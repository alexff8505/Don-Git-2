import Foundation

enum GitDiffParser {
    /// Git's -z formats preserve tabs, newlines, spaces, and Unicode in file names.
    static func files(statusOutput: String, statOutput: String) throws -> [CommitChangedFile] {
        let statusTokens = statusOutput.split(separator: "\0", omittingEmptySubsequences: false)
        var paths: [(status: String, path: String, previous: String?)] = []
        var index = 0
        while index < statusTokens.count, !statusTokens[index].isEmpty {
            let status = String(statusTokens[index])
            index += 1
            guard index < statusTokens.count else { throw GitClient.GitClientError.invalidOutput }
            let firstPath = String(statusTokens[index])
            index += 1
            if status.hasPrefix("R") || status.hasPrefix("C") {
                guard index < statusTokens.count else { throw GitClient.GitClientError.invalidOutput }
                paths.append((status, String(statusTokens[index]), firstPath))
                index += 1
            } else {
                paths.append((status, firstPath, nil))
            }
        }

        let statTokens = statOutput.split(separator: "\0", omittingEmptySubsequences: false)
        var stats: [String: (Int?, Int?)] = [:]
        index = 0
        while index < statTokens.count, !statTokens[index].isEmpty {
            // Only split the first two tabs: the file path may itself contain tabs.
            let fields = statTokens[index].split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { throw GitClient.GitClientError.invalidOutput }
            index += 1
            let path: String
            if fields[2].isEmpty {
                // A rename is encoded as counts<TAB><NUL>old<NUL>new<NUL>.
                guard index + 1 < statTokens.count else { throw GitClient.GitClientError.invalidOutput }
                path = String(statTokens[index + 1])
                index += 2
            } else {
                path = String(fields[2])
            }
            stats[path] = (Int(fields[0]), Int(fields[1]))
        }
        return try paths.map { entry in
            guard let counts = stats[entry.path] else { throw GitClient.GitClientError.invalidOutput }
            return CommitChangedFile(path: entry.path, previousPath: entry.previous, status: entry.status,
                                     additions: counts.0, deletions: counts.1)
        }
    }

    /// A renamed file's old path can also contain a newly added file. Use exact raw
    /// paths to choose its patch, rather than showing every patch for both pathspecs.
    static func patch(for path: String, in output: String) throws -> String {
        guard !output.isEmpty else { return "" }
        guard let separator = output.range(of: "\0\0") else { throw GitClient.GitClientError.invalidOutput }
        let tokens = output[..<separator.lowerBound].split(separator: "\0", omittingEmptySubsequences: false)
        var paths: [String] = []
        var index = 0
        while index < tokens.count {
            let status = tokens[index].split(separator: " ").last ?? ""
            index += 1
            guard index < tokens.count else { throw GitClient.GitClientError.invalidOutput }
            if status.hasPrefix("R") || status.hasPrefix("C") {
                index += 1
                guard index < tokens.count else { throw GitClient.GitClientError.invalidOutput }
            }
            paths.append(String(tokens[index]))
            index += 1
        }
        let patches = output[separator.upperBound...].components(separatedBy: "\ndiff --git ")
        guard patches.count == paths.count, let selected = paths.firstIndex(of: path) else {
            throw GitClient.GitClientError.invalidOutput
        }
        let selectedPatch = patches[selected]
        return (selected == 0 ? "" : "diff --git ") + selectedPatch + (selectedPatch.hasSuffix("\n") ? "" : "\n")
    }

    static func diff(_ patch: String) -> FileDiff {
        let hunkPattern = /@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/
        var lines: [DiffLine] = []
        var oldNumber = 0
        var newNumber = 0
        var inHunk = false
        var isBinary = false
        func append(_ kind: DiffLine.Kind, _ text: String, old: Int? = nil, new: Int? = nil) {
            lines.append(DiffLine(id: lines.count, kind: kind, text: text, oldNumber: old, newNumber: new))
        }
        for rawLine in patch.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            let line = String(rawLine)
            if let match = line.firstMatch(of: hunkPattern) {
                oldNumber = Int(match.1) ?? 0
                newNumber = Int(match.2) ?? 0
                inHunk = true
                append(.hunk, line)
            } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
                isBinary = true
                append(.notice, "Binary file contents differ.")
            } else if inHunk {
                switch line.first {
                case " ":
                    append(.context, String(line.dropFirst()), old: oldNumber, new: newNumber)
                    oldNumber += 1
                    newNumber += 1
                case "-":
                    append(.deletion, String(line.dropFirst()), old: oldNumber)
                    oldNumber += 1
                case "+":
                    append(.addition, String(line.dropFirst()), new: newNumber)
                    newNumber += 1
                case "\\": append(.notice, line)
                default: break
                }
            } else if line.hasPrefix("old mode ") || line.hasPrefix("new mode ") || line.hasPrefix("new file mode ")
                        || line.hasPrefix("deleted file mode ") || line.hasPrefix("similarity index ")
                        || line.hasPrefix("rename from ") || line.hasPrefix("rename to ") {
                append(.notice, line)
            }
        }
        return FileDiff(lines: lines, isBinary: isBinary)
    }
}
