#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dongit-changes-checks.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
swiftc -swift-version 6 -parse-as-library -module-cache-path "$TEST_DIR/cache" \
    Models/GitCommit.swift Models/GitRepository.swift Models/CommitChanges.swift \
    Support/DateParsers.swift Support/GitRefParser.swift Support/GitDiffParser.swift \
    Services/GitClient.swift Services/CommitGraphBuilder.swift Stores/CommitChangesStore.swift \
    Tests/CommitChangesTests.swift -o "$TEST_DIR/changes-checks"
"$TEST_DIR/changes-checks"
