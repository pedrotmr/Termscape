#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
REPO_DIR="$ROOT_DIR"

if [[ -f "$ROOT_DIR/Scripts/release/config.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/Scripts/release/config.env"
fi

APP_NAME=${APP_NAME:-Termscape}
XCODE_SCHEME=${XCODE_SCHEME:-Termscape}
XCODE_PROJECT=${XCODE_PROJECT:-Termscape.xcodeproj}
XCODE_CONFIGURATION=${XCODE_CONFIGURATION:-Release}

RELEASE_DIR=${RELEASE_DIR:-$ROOT_DIR/build/release}
ARCHIVE_PATH=${ARCHIVE_PATH:-$RELEASE_DIR/${APP_NAME}.xcarchive}
DIST_DIR=${DIST_DIR:-$RELEASE_DIR/dist}
TOOLS_DIR=${TOOLS_DIR:-$RELEASE_DIR/tools}
APPCAST_ARCHIVES_DIR=${APPCAST_ARCHIVES_DIR:-$RELEASE_DIR/appcast-archives}

SPARKLE_FEED_URL=${SPARKLE_FEED_URL:-https://github.com/pedrotmr/termscape/releases/latest/download/appcast-preview.xml}
SPARKLE_DOWNLOAD_URL_PREFIX=${SPARKLE_DOWNLOAD_URL_PREFIX:-}
SPARKLE_RELEASE_NOTES_URL_PREFIX=${SPARKLE_RELEASE_NOTES_URL_PREFIX:-}
SPARKLE_CHANNEL=${SPARKLE_CHANNEL:-}
SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY:-}
SPARKLE_PRIVATE_KEY=${SPARKLE_PRIVATE_KEY:-}

RELEASE_MODE=${RELEASE_MODE:-preview}
APPCAST_FILENAME=${APPCAST_FILENAME:-appcast-preview.xml}

if [[ -n "${GITHUB_REF_NAME:-}" ]]; then
  VERSION_TAG=${GITHUB_REF_NAME#v}
elif [[ -n "${RELEASE_VERSION:-}" ]]; then
  VERSION_TAG=$RELEASE_VERSION
else
  VERSION_TAG=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Info.plist")
fi

ZIP_PATH=${ZIP_PATH:-$DIST_DIR/${APP_NAME}-${VERSION_TAG}.zip}
DMG_PATH=${DMG_PATH:-$DIST_DIR/${APP_NAME}-${VERSION_TAG}.dmg}
APPCAST_PATH=${APPCAST_PATH:-$DIST_DIR/$APPCAST_FILENAME}
APP_PATH="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"

log() {
  echo "[release] $*" >&2
}

fail() {
  echo "[release] error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

write_github_output() {
  local key=$1
  local value=$2
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  fi
}

ensure_dirs() {
  mkdir -p "$RELEASE_DIR" "$DIST_DIR" "$TOOLS_DIR" "$APPCAST_ARCHIVES_DIR"
}

# Before xcodebuild: set CFBundleShortVersionString / CFBundleVersion from the git tag so Sparkle
# and GitHub release tags stay aligned (source Info.plist can stay at a dev default).
sync_info_plist_version_from_tag() {
  [[ "${RELEASE_SKIP_VERSION_SYNC:-}" == "1" ]] && return 0
  [[ -z "${GITHUB_REF_NAME:-}" ]] && return 0
  # Require v1.x style tags (v + digit), e.g. v1.2.3 or v1.0
  [[ "$GITHUB_REF_NAME" =~ ^v[0-9] ]] || return 0

  require_cmd /usr/libexec/PlistBuddy

  local short=$VERSION_TAG
  local build

  if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    build="$GITHUB_RUN_NUMBER"
  else
    build=$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || true)
    if [[ -z "$build" ]]; then
      build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ROOT_DIR/Info.plist" 2>/dev/null || echo "1")
    fi
  fi

  log "syncing Info.plist versions from tag (Sparkle): CFBundleShortVersionString=$short CFBundleVersion=$build (tag=$GITHUB_REF_NAME)"

  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $short" "$ROOT_DIR/Info.plist" \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $short" "$ROOT_DIR/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$ROOT_DIR/Info.plist" \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build" "$ROOT_DIR/Info.plist"

  write_github_output "cf_bundle_short_version_string" "$short"
  write_github_output "cf_bundle_version" "$build"
}
