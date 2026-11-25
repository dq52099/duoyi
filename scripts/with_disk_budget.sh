#!/usr/bin/env bash
# For commands which do not already acquire the shared Flutter lock.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIN_FREE_GIB=12
BUILD_ARGS=()
if [[ "${1:-}" == --build ]]; then
  MIN_FREE_GIB=25
  BUILD_ARGS=(--build)
  export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/home/ubuntu/duoyi-gradle-cache-20261010}"
  shift
fi
if [[ "${1:-}" == -- ]]; then shift; fi
if [[ "$#" -eq 0 ]]; then
  echo 'Usage: bash scripts/with_disk_budget.sh [--build] -- command [args...]' >&2
  exit 2
fi
python3 "$ROOT_DIR/scripts/disk_budget.py" check --min-free-gib "$MIN_FREE_GIB"
exec python3 "$ROOT_DIR/scripts/resource_guard.py" \
  --min-free-gib "$MIN_FREE_GIB" "${BUILD_ARGS[@]}" -- "$@"
