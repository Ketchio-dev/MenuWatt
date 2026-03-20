#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build-app/MenuWatt.app}"
OUTPUT_DIR="${2:-$ROOT_DIR/.build-app}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MenuWattDmg.XXXXXX")"
VOLUME_NAME="${MENUWATT_DMG_VOLUME_NAME:-MenuWatt}"

fail() {
  echo "$1" >&2
  exit 1
}

cleanup() {
  rm -rf "$STAGING_DIR"
}

trap cleanup EXIT

if [[ ! -d "$APP_PATH" ]]; then
  fail "Expected app bundle at $APP_PATH"
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  fail "hdiutil is required to package a DMG."
fi

mkdir -p "$OUTPUT_DIR"

APP_NAME="$(basename "$APP_PATH" .app)"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
APP_VERSION=""

if [[ -f "$INFO_PLIST" ]]; then
  APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)"
fi

DMG_NAME="$APP_NAME.dmg"
if [[ -n "$APP_VERSION" ]]; then
  DMG_NAME="$APP_NAME-$APP_VERSION.dmg"
fi

DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Packaged DMG at:"
echo "$DMG_PATH"
