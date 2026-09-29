#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dongit-graph-checks.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
    Models/GitCommit.swift Models/GitRepository.swift \
    Support/DateParsers.swift Support/GitRefParser.swift \
    Services/GitClient.swift Services/CommitGraphBuilder.swift \
    Tests/CommitGraphTests.swift -o "$TEST_DIR/graph-checks"
"$TEST_DIR/graph-checks"
