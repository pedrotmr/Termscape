#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

HOOKS_DIR="${ROOT}/Scripts/git-hooks"
git config core.hooksPath "${HOOKS_DIR}"
echo "Set core.hooksPath to ${HOOKS_DIR}"
echo "pre-commit: SwiftLint --fix, SwiftFormat ., git add Sources Tests, SwiftLint lint."
echo "Install tools once: bash Scripts/ci/bootstrap-tooling.sh"
