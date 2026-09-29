#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dongit-column-checks.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
swiftc -parse-as-library -module-cache-path "$TEST_DIR/cache" \
    Views/CommitTableColumnPersistence.swift Tests/ColumnPersistenceTests.swift \
    -o "$TEST_DIR/column-checks"
"$TEST_DIR/column-checks"
