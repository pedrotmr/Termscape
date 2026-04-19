#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

HOOKS_DIR="${ROOT}/.githooks"
if [[ ! -f "${HOOKS_DIR}/pre-commit" ]]; then
  echo "error: ${HOOKS_DIR}/pre-commit is missing (hooks must be committed in the repo)." >&2
  exit 1
fi

git config core.hooksPath .githooks
echo "Git hooks enabled: core.hooksPath=.githooks"
echo "pre-commit runs SwiftFormat + SwiftLint; LFS hooks live alongside in .githooks/."
