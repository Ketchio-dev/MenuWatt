#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MenuWatt"
ARTIFACT_DIR="$ROOT_DIR/.build-app"
DERIVED_DATA_DIR="$ROOT_DIR/.build-app-derived"
BUILD_LOG="$ARTIFACT_DIR/xcodebuild.log"
XCODEGEN_LOG="$ARTIFACT_DIR/xcodegen.log"
SOURCE_PACKAGES_DIR="$ROOT_DIR/.build-xcode-packages"
XCODEGEN_BIN="${XCODEGEN_BIN:-}"

fail() {
  echo "$1" >&2
  exit 1
}

find_xcode_developer_dir() {
  local candidate

  for candidate in \
    "/Applications/Xcode.app/Contents/Developer" \
    "$HOME/Applications/Xcode.app/Contents/Developer"; do
    if [[ -d "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  for candidate in /Volumes/*/Applications/Xcode.app/Contents/Developer; do
    if [[ -d "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

select_developer_dir() {
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    return
  fi

  local selected_dir
  selected_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$selected_dir" == "/Library/Developer/CommandLineTools" ]]; then
    local discovered_dir
    discovered_dir="$(find_xcode_developer_dir || true)"
    if [[ -n "$discovered_dir" ]]; then
      export DEVELOPER_DIR="$discovered_dir"
    fi
  fi
}

ensure_xcodebuild_usable() {
  select_developer_dir

  if ! xcodebuild -version >/dev/null 2>&1; then
    fail "Full Xcode is required to build MenuWatt.app. Install Xcode and select it with xcode-select."
  fi
}

resolve_xcodegen() {
  if [[ -n "$XCODEGEN_BIN" ]] && [[ -x "$XCODEGEN_BIN" ]]; then
    return
  fi

  if command -v xcodegen >/dev/null 2>&1; then
    XCODEGEN_BIN="$(command -v xcodegen)"
    return
  fi

  for XCODEGEN_BIN in \
    "/opt/homebrew/bin/xcodegen" \
    "/opt/homebrew/opt/xcodegen/bin/xcodegen" \
    "/usr/local/bin/xcodegen"; do
    if [[ -x "$XCODEGEN_BIN" ]]; then
      return
    fi
  done

  local brew_prefix
  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix xcodegen 2>/dev/null || true)"
  elif [[ -x "/opt/homebrew/bin/brew" ]]; then
    brew_prefix="$(/opt/homebrew/bin/brew --prefix xcodegen 2>/dev/null || true)"
  else
    brew_prefix=""
  fi
  if [[ -n "$brew_prefix" ]] && [[ -x "$brew_prefix/bin/xcodegen" ]]; then
    XCODEGEN_BIN="$brew_prefix/bin/xcodegen"
    return
  fi

  fail "xcodegen is required because project.yml is the source of truth for MenuWatt.xcodeproj."
}

generate_xcode_project() {
  [[ -f "$ROOT_DIR/project.yml" ]] || fail "Missing project.yml; cannot generate Xcode project."
  resolve_xcodegen

  echo "Generating Xcode project from project.yml..."
  if ! "$XCODEGEN_BIN" generate --spec "$ROOT_DIR/project.yml" >"$XCODEGEN_LOG" 2>&1; then
    echo "xcodegen failed. See log: $XCODEGEN_LOG" >&2
    exit 1
  fi
}

resign_app_bundle() {
  local app_path="$1"

  echo "Re-signing final app bundle..."
  codesign --force --deep --sign - "$app_path"
  codesign --verify --deep --strict "$app_path"
}

cd "$ROOT_DIR"

mkdir -p "$ARTIFACT_DIR"
mkdir -p "$DERIVED_DATA_DIR"
mkdir -p "$SOURCE_PACKAGES_DIR"

ensure_xcodebuild_usable
generate_xcode_project

echo "Building $APP_NAME with Xcode..."
if ! xcodebuild \
  -project "$ROOT_DIR/MenuWatt.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  build >"$BUILD_LOG" 2>&1; then
  if grep -q "You have not agreed to the Xcode license agreements" "$BUILD_LOG"; then
    echo "xcodebuild is blocked by the Xcode license agreement." >&2
    echo "Run 'sudo xcodebuild -license accept' once, then rerun ./scripts/build-app.sh." >&2
    exit 1
  fi
  echo "xcodebuild failed. See log: $BUILD_LOG" >&2
  tail -n 40 "$BUILD_LOG" >&2 || true
  exit 1
fi

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
resign_app_bundle "$APP_DIR"

echo "Built app bundle at:"
echo "$APP_DIR"
