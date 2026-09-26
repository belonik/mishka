#!/bin/bash
#
# Builds and runs every check suite.
#
#   ./Tests/run-tests.sh
#
# The suites are plain executables rather than XCTest bundles: the app ships as a SwiftPM
# executable target, which a test bundle cannot import. Each suite is compiled together with
# the sources it covers, so it exercises the shipped code rather than a copy of it.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
MODULE_CACHE="${CLANG_MODULE_CACHE_PATH:-$ROOT/.dsh-modulecache}"
BIN="$ROOT/.build/checks"
mkdir -p "$MODULE_CACHE" "$BIN"

APP="$ROOT/Sources/Mishka"

# Sources needed by more than one suite.
CORE=(
    "$APP/Support/Utilities.swift"
    "$APP/Models/Note.swift"
    "$APP/Models/Tag.swift"
    "$APP/Storage/NoteStore.swift"
)

run_suite() {
    local name="$1"
    local binary="$BIN/$name"
    shift

    swiftc -module-cache-path "$MODULE_CACHE" \
        -o "$binary" \
        "$ROOT/Tests/Checks.swift" \
        "$@" \
        "$ROOT/Tests/$name/main.swift"

    "$binary"
}

run_suite Titles \
    "$APP/Support/Utilities.swift" \
    "$APP/Models/Note.swift" \
    "$APP/Models/Tag.swift"

run_suite Store "${CORE[@]}"

run_suite Subscriptions \
    "$APP/Support/Utilities.swift" \
    "$APP/Support/Exporter.swift" \
    "$APP/Models/Note.swift" \
    "$APP/Models/Tag.swift" \
    "$APP/Storage/NoteStore.swift" \
    "$APP/Theme/Theme.swift" \
    "$APP/Theme/ThemeCatalog.swift" \
    "$APP/Markdown/MarkdownRenderer.swift" \
    "$APP/Editor/MarkdownHighlighter.swift" \
    "$APP/Views/PreviewPane.swift" \
    "$APP/App/Settings.swift" \
    "$APP/App/AppState.swift"

echo "All suites passed."
