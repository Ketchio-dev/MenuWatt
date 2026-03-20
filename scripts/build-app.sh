#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MenuWatt"
ARTIFACT_DIR="$ROOT_DIR/.build-app"
DERIVED_DATA_DIR="$ROOT_DIR/.build-app-derived"
BUILD_LOG="$ARTIFACT_DIR/xcodebuild.log"

cd "$ROOT_DIR"

mkdir -p "$ARTIFACT_DIR"
mkdir -p "$DERIVED_DATA_DIR"

echo "Building $APP_NAME with Xcode..."
xcodebuild \
  -project "$ROOT_DIR/MenuWatt.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -disableAutomaticPackageResolution \
  build >"$BUILD_LOG" 2>&1

APP_BUILD_DIR="$DERIVED_DATA_DIR/Build/Products/Release"
SOURCE_APP_DIR="$APP_BUILD_DIR/${APP_NAME}.app"
APP_DIR="$ARTIFACT_DIR/${APP_NAME}.app"

if [[ ! -d "$SOURCE_APP_DIR" ]]; then
  echo "Could not locate built app bundle at $SOURCE_APP_DIR" >&2
  echo "See build log: $BUILD_LOG" >&2
  exit 1
fi

rm -rf "$APP_DIR"
ditto "$SOURCE_APP_DIR" "$APP_DIR"

echo "Built app bundle at:"
echo "$APP_DIR"
