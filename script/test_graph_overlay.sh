#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dongit-graph-overlay-checks.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT_DIR"
swiftc -swift-version 6 -parse-as-library -module-cache-path "$ROOT_DIR/.build/ModuleCache" \
    Models/GitCommit.swift Support/CommitGraphGeometry.swift Support/CommitGraphColors.swift Support/GitGraphColorPalette.swift \
    Views/CommitGraphView.swift Views/CommitGraphOverlay.swift Tests/GraphOverlayTests.swift \
    -o "$TEST_DIR/graph-overlay-checks"
"$TEST_DIR/graph-overlay-checks"
