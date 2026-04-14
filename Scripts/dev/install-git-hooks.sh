#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

chmod +x "$ROOT_DIR/.githooks/pre-commit"
git -C "$ROOT_DIR" config core.hooksPath .githooks

echo "Configured git hooks for this repository."
echo "Hooks path: $(git -C "$ROOT_DIR" config --get core.hooksPath)"
