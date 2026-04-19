#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

bash "${ROOT}/Scripts/ci/bootstrap-tooling.sh"
export PATH="${ROOT}/build/ci-tools/bin:${PATH}"

DERIVED_DATA="${ROOT}/build/DerivedData"
mkdir -p "${DERIVED_DATA}"

echo "== swiftformat (lint) =="
swiftformat Sources Tests --lint

echo "== swiftlint =="
swiftlint lint

echo "== xcodebuild test =="
xcodebuild \
  -project Termscape.xcodeproj \
  -scheme Termscape \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  test
