#!/bin/bash
# Builds and runs the FilenameFixer test suite.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

swiftc -o "$BUILD_DIR/fixer_test" \
    "$REPO_ROOT/Extension/FilenameFixer.swift" \
    "$REPO_ROOT/Extension/EncodedWord.swift" \
    "$REPO_ROOT/Extension/MojibakeRepair.swift" \
    "$REPO_ROOT/tests/main.swift"
"$BUILD_DIR/fixer_test"
