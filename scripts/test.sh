#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MenuWattTest.XXXXXX")"
TEST_HOME="$ROOT_DIR/.build-home"
CACHE_DIR="$ROOT_DIR/.build-cache"
CLANG_MODULE_CACHE_DIR="$ROOT_DIR/.build-clang-module-cache"
LOG_FILE="$SCRATCH_DIR/swift-test.log"

cleanup() {
  rm -rf "$SCRATCH_DIR"
}

trap cleanup EXIT

cd "$ROOT_DIR"
mkdir -p "$TEST_HOME/Library/Caches" "$TEST_HOME/Library/org.swift.swiftpm" "$CACHE_DIR" "$CLANG_MODULE_CACHE_DIR"

export HOME="$TEST_HOME"
export XDG_CACHE_HOME="$CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_DIR"

set +e
swift test --scratch-path "$SCRATCH_DIR" "$@" >"$LOG_FILE" 2>&1
exit_code=$?
set -e

cat "$LOG_FILE"

if [[ $exit_code -ne 0 ]]; then
  if grep -q "this SDK is not supported by the compiler" "$LOG_FILE"; then
    echo >&2
    echo "MenuWatt tests require a matching Swift toolchain and macOS SDK." >&2
    echo "Install/select a matching full Xcode or reinstall Command Line Tools, then retry." >&2
  fi
  exit $exit_code
fi
