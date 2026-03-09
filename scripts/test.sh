#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MenuWattTest.XXXXXX")"

cleanup() {
  rm -rf "$SCRATCH_DIR"
}

trap cleanup EXIT

cd "$ROOT_DIR"
swift test --scratch-path "$SCRATCH_DIR" "$@"
