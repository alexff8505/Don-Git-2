#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dongit-diff-view-checks.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
swiftc -swift-version 6 -parse-as-library -module-cache-path "$TEST_DIR/cache" \
    Models/CommitChanges.swift Support/AppNotifications.swift Views/DiffCodeView.swift Views/NativeSplitView.swift \
    Tests/DiffViewTests.swift -o "$TEST_DIR/diff-view-checks"
"$TEST_DIR/diff-view-checks"
