#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/tooling/tool-versions"

DEST="${ROOT}/build/ci-tools/bin"
STAMP_DIR="${ROOT}/build/ci-tools"
mkdir -p "${DEST}"

install_swiftformat() {
  local tmp
  tmp="$(mktemp -d)"
  # Expand path when registering the trap (not on EXIT) so a failing step does not
  # hit `set -u` with an out-of-scope `tmp`, and each install owns its cleanup.
  trap "rm -rf \"$tmp\"" EXIT
  curl -fsSL --retry 3 --connect-timeout 20 --max-time 300 \
    -o "${tmp}/swiftformat.zip" \
    "https://github.com/nicklockwood/SwiftFormat/releases/download/${SWIFTFORMAT_VERSION}/swiftformat.zip"
  echo "${SWIFTFORMAT_ZIP_SHA256}  ${tmp}/swiftformat.zip" | shasum -a 256 -c -
  unzip -oq "${tmp}/swiftformat.zip" -d "${tmp}"
  install -m 0755 "${tmp}/swiftformat" "${DEST}/swiftformat"
  printf '%s\n' "${SWIFTFORMAT_VERSION}" >"${STAMP_DIR}/.swiftformat-version"
  trap - EXIT
  rm -rf "${tmp}"
}

install_swiftlint() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf \"$tmp\"" EXIT
  curl -fsSL --retry 3 --connect-timeout 20 --max-time 300 \
    -o "${tmp}/swiftlint.zip" \
    "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"
  echo "${SWIFTLINT_ZIP_SHA256}  ${tmp}/swiftlint.zip" | shasum -a 256 -c -
  unzip -oq "${tmp}/swiftlint.zip" -d "${tmp}"
  install -m 0755 "${tmp}/swiftlint" "${DEST}/swiftlint"
  printf '%s\n' "${SWIFTLINT_VERSION}" >"${STAMP_DIR}/.swiftlint-version"
  trap - EXIT
  rm -rf "${tmp}"
}

if [[ ! -f "${STAMP_DIR}/.swiftformat-version" ]] || [[ "$(cat "${STAMP_DIR}/.swiftformat-version")" != "${SWIFTFORMAT_VERSION}" ]] || [[ ! -x "${DEST}/swiftformat" ]]; then
  install_swiftformat
fi

if [[ ! -f "${STAMP_DIR}/.swiftlint-version" ]] || [[ "$(cat "${STAMP_DIR}/.swiftlint-version")" != "${SWIFTLINT_VERSION}" ]] || [[ ! -x "${DEST}/swiftlint" ]]; then
  install_swiftlint
fi

echo "Tooling ready at ${DEST} (swiftformat ${SWIFTFORMAT_VERSION}, swiftlint ${SWIFTLINT_VERSION})"
