#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MenuWatt"
ARTIFACT_DIR="$ROOT_DIR/.build-app"
SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MenuWattBuild.XXXXXX")"

cleanup() {
  rm -rf "$SCRATCH_DIR"
}

trap cleanup EXIT

cd "$ROOT_DIR"

swift build -c release --scratch-path "$SCRATCH_DIR"

BIN_PATH="$(find "$SCRATCH_DIR" -type f -path "*/release/$APP_NAME" | head -n 1)"
if [[ -z "$BIN_PATH" ]]; then
  echo "Could not locate release binary for $APP_NAME" >&2
  exit 1
fi

mkdir -p "$ARTIFACT_DIR"
APP_DIR="$ARTIFACT_DIR/${APP_NAME}.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$ROOT_DIR/Packaging/Resources/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Packaging/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built app bundle at:"
echo "$APP_DIR"
