#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dongit-local-checks.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
swiftc -swift-version 6 -parse-as-library -module-cache-path "$ROOT_DIR/.build/ModuleCache" \
    Models/GitCommit.swift Models/GitRepository.swift Models/CommitChanges.swift Models/RepositoryFolderColor.swift \
    Support/DateParsers.swift Support/GitRefParser.swift Support/GitDiffParser.swift \
    Services/GitClient.swift Services/CommitGraphBuilder.swift Services/GitRepositoryScanner.swift \
    Stores/GitViewerStore.swift Stores/CommitChangesStore.swift Tests/LocalChangesTests.swift -o "$TEST_DIR/local-checks"
"$TEST_DIR/local-checks"
