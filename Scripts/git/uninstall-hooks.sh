#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

git config --unset core.hooksPath || true
echo "Removed core.hooksPath (default .git/hooks is active again)."
