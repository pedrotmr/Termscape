#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-fix}"
shift || true
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INPUT_TARGETS=("$@")
TARGETS=()
LINT_TARGETS=()

usage() {
  cat <<'USAGE'
Usage: Scripts/dev/style.sh [fix|check] [path ...]

Modes:
  fix    Run auto-format + auto-fix locally.
  check  Run check-only mode for CI.

If no paths are provided, defaults to project Swift source folders.
USAGE
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool '$tool' is not installed or not on PATH" >&2
    exit 1
  fi
}

collect_targets() {
  local -a defaults=()
  local target

  if [[ ${#INPUT_TARGETS[@]} -eq 0 ]]; then
    for target in Sources Tests Scripts; do
      if [[ -e "$target" ]]; then
        defaults+=("$target")
      fi
    done
    if [[ ${#defaults[@]} -eq 0 ]]; then
      defaults=(.)
    fi
  else
    defaults=("${INPUT_TARGETS[@]}")
  fi

  for target in "${defaults[@]}"; do
    if [[ "$target" == vendor/* || "$target" == ./vendor/* ]]; then
      continue
    fi
    TARGETS+=("$target")
  done
}

collect_lint_targets() {
  local target
  for target in "${TARGETS[@]}"; do
    if [[ -f "$target" ]]; then
      if [[ "$target" == *.swift ]]; then
        LINT_TARGETS+=("$target")
      fi
      continue
    fi

    if [[ -d "$target" ]]; then
      if find "$target" -type f -name '*.swift' -print -quit | grep -q .; then
        LINT_TARGETS+=("$target")
      fi
    fi
  done
}

run_fix() {
  echo "Running swiftformat on ${#TARGETS[@]} target(s)"
  swiftformat "${TARGETS[@]}"

  if [[ ${#LINT_TARGETS[@]} -eq 0 ]]; then
    echo "No Swift files matched lint targets. Skipping SwiftLint."
    return
  fi

  echo "Running swiftlint --fix on ${#LINT_TARGETS[@]} target(s)"
  swiftlint --fix "${LINT_TARGETS[@]}"
}

run_check() {
  echo "Running swiftformat --lint on ${#TARGETS[@]} target(s)"
  swiftformat --lint "${TARGETS[@]}"

  if [[ ${#LINT_TARGETS[@]} -eq 0 ]]; then
    echo "No Swift files matched lint targets. Skipping SwiftLint."
    return
  fi

  echo "Running swiftlint lint --strict on ${#LINT_TARGETS[@]} target(s)"
  swiftlint lint --strict "${LINT_TARGETS[@]}"
}

if [[ "$MODE" == "-h" || "$MODE" == "--help" ]]; then
  usage
  exit 0
fi

require_tool swiftformat
require_tool swiftlint

cd "$ROOT_DIR"
collect_targets
collect_lint_targets

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "No targets to process."
  exit 0
fi

case "$MODE" in
  fix)
    run_fix
    ;;
  check)
    run_check
    ;;
  *)
    usage
    exit 1
    ;;
esac
