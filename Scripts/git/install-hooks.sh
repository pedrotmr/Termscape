#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

git config core.hooksPath .githooks
echo "Git hooks enabled: core.hooksPath=.githooks"
echo "pre-commit runs SwiftFormat + SwiftLint (see .githooks/pre-commit)."
