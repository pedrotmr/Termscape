#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

bash "${ROOT}/Scripts/ci/bootstrap-tooling.sh"
export PATH="${ROOT}/build/ci-tools/bin:${PATH}"

echo "== swiftformat (lint) =="
swiftformat Sources Tests --lint

echo "== swiftlint =="
swiftlint lint
