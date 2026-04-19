#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

bash "${ROOT}/Scripts/ci/format-lint.sh"

DERIVED_DATA="${ROOT}/build/DerivedData"
mkdir -p "${DERIVED_DATA}"

echo "== xcodebuild test =="
xcodebuild \
  -project Termscape.xcodeproj \
  -scheme Termscape \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  test
