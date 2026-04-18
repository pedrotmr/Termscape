#!/usr/bin/env bash
set -euo pipefail

# GhosttyKit is tracked via Git LFS; checkout uses lfs: true in CI.
# This script verifies the framework is present and refreshes LFS if needed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if command -v git >/dev/null 2>&1 && git lfs version >/dev/null 2>&1; then
  GIT_TERMINAL_PROMPT=0 git lfs pull 2>/dev/null || true
fi

XCFW="Resources/GhosttyKit.xcframework"
if [[ ! -d "$XCFW" ]] || [[ ! -f "$XCFW/Info.plist" ]]; then
  echo "::error::Expected $XCFW (run 'git lfs pull' locally if missing)."
  exit 1
fi

echo "GhosttyKit.xcframework OK"
