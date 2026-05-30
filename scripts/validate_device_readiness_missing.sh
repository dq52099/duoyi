#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/build/device-readiness-missing/latest}"
MISSING_TSV="$REPORT_DIR/missing.tsv"
MISSING_MD="$REPORT_DIR/missing.md"
failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

require_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    fail "missing file: $file"
    return 1
  fi
  if [[ ! -s "$file" ]]; then
    fail "empty file: $file"
    return 1
  fi
}

require_file "$MISSING_TSV" || true
require_file "$MISSING_MD" || true

if [[ -f "$MISSING_TSV" ]]; then
  header="$(head -n 1 "$MISSING_TSV")"
  if [[ "$header" != $'check\tdetail' ]]; then
    fail "missing.tsv header is invalid"
  fi
  row_count=$(( $(wc -l < "$MISSING_TSV") - 1 ))
  if [[ "$row_count" -lt 1 ]]; then
    fail "missing.tsv must contain at least one missing readiness row"
  fi
  while IFS=$'\t' read -r check detail extra; do
    [[ "$check" == "check" ]] && continue
    if [[ -n "${extra:-}" ]]; then
      fail "missing.tsv row has too many columns for $check"
    fi
    if [[ -z "$check" || -z "$detail" ]]; then
      fail "missing.tsv row has empty fields"
    fi
  done < "$MISSING_TSV"
fi

if [[ -f "$MISSING_MD" ]]; then
  for marker in 'Missing Device Readiness' '| Check | Detail |'; do
    if ! grep -Fq "$marker" "$MISSING_MD"; then
      fail "missing.md missing marker: $marker"
    fi
  done
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Missing device readiness validation failed with $failures issue(s)." >&2
  exit 1
fi

echo "Missing device readiness validation passed."
