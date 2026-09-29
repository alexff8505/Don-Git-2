#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dongit-selection-checks.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
swiftc -swift-version 6 -parse-as-library -module-cache-path "$TEST_DIR/cache" \
    Models/GitCommit.swift Models/GitRepository.swift Models/CommitChanges.swift Models/RepositoryFolderColor.swift \
    Support/DateParsers.swift Support/GitRefParser.swift Support/GitDiffParser.swift \
    Services/GitClient.swift Services/CommitGraphBuilder.swift Services/GitRepositoryScanner.swift \
    Stores/GitViewerStore.swift Tests/RepositorySelectionTests.swift -o "$TEST_DIR/selection-checks"
"$TEST_DIR/selection-checks"
