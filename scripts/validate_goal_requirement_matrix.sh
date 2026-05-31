#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX_FILE="${MATRIX_FILE:-$ROOT_DIR/docs/goal-requirement-matrix.md}"
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

require_contains() {
  local file="$1"
  local marker="$2"
  local label="$3"
  if ! grep -Fq "$marker" "$file"; then
    fail "$label missing marker: $marker"
  fi
}

trim() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

normalize_evidence_path() {
  local evidence="$1"
  local linked=""
  evidence="$(trim "$evidence")"
  evidence="${evidence//\`/}"
  linked="$(printf '%s' "$evidence" | sed -nE 's/^\[[^]]*\]\(([^)]*)\)$/\1/p')"
  if [[ -n "$linked" ]]; then
    evidence="$linked"
  fi
  trim "$evidence"
}

clean_evidence_path() {
  local evidence="$1"
  evidence="$(trim "$evidence")"
  evidence="${evidence//\`/}"
  evidence="${evidence%%#*}"
  evidence="$(printf '%s' "$evidence" | sed -E 's/^[<"[:space:]]+//; s/[>",.;[:space:]]+$//')"
  trim "$evidence"
}

is_local_evidence_path() {
  local evidence="$1"
  [[ -n "$evidence" ]] || return 1
  [[ "$evidence" == http://* || "$evidence" == https://* ]] && return 1
  [[ "$evidence" == *"://"* ]] && return 1
  [[ "$evidence" == */* ]] || return 1
  [[ "$evidence" =~ ^[A-Za-z0-9._/@+-]+$ ]]
}

extract_local_evidence_paths() {
  local evidence_column="$1"
  local raw_evidence=""
  local normalized=""
  local token_source=""
  local token=""
  local evidence=""

  IFS=';' read -ra evidence_items <<< "$evidence_column"
  for raw_evidence in "${evidence_items[@]}"; do
    normalized="$(normalize_evidence_path "$raw_evidence")"
    normalized="$(clean_evidence_path "$normalized")"
    if is_local_evidence_path "$normalized"; then
      printf '%s\n' "$normalized"
      continue
    fi

    token_source="$(printf '%s' "$raw_evidence" | tr '`[]()<>,|' '         ')"
    for token in $token_source; do
      evidence="$(clean_evidence_path "$token")"
      if is_local_evidence_path "$evidence"; then
        printf '%s\n' "$evidence"
      fi
    done
  done | awk '!seen[$0]++'
}

require_evidence_file() {
  local id="$1"
  local evidence="$2"
  local file="$ROOT_DIR/$evidence"
  if [[ "$evidence" == /* ]]; then
    file="$evidence"
  fi
  if [[ "$evidence" == .. || "$evidence" == ../* || "$evidence" == */../* || "$evidence" == */.. ]]; then
    fail "$id evidence path must stay under the repository: $evidence"
    return 1
  fi
  if [[ "$evidence" == /* && "$evidence" != "$ROOT_DIR"/* ]]; then
    fail "$id evidence path must stay under the repository: $evidence"
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    fail "$id evidence path is missing: $evidence"
    return 1
  fi
  if [[ ! -s "$file" ]]; then
    fail "$id evidence path is empty: $evidence"
    return 1
  fi
}

validate_evidence_paths() {
  local line=""
  local id=""
  local evidence_column=""
  local evidence=""
  local local_evidence_count=0

  while IFS= read -r line; do
    [[ "$line" == \|\ REQ-* ]] || continue
    id="$(printf '%s' "$line" | awk -F '|' '{ gsub(/^ +| +$/, "", $2); print $2 }')"
    evidence_column="$(printf '%s' "$line" | awk -F '|' '{ gsub(/^ +| +$/, "", $5); print $5 }')"
    local_evidence_count=0

    while IFS= read -r evidence; do
      [[ -n "$evidence" ]] || continue
      local_evidence_count=$((local_evidence_count + 1))
      require_evidence_file "$id" "$evidence" || true
    done < <(extract_local_evidence_paths "$evidence_column")

    if [[ "$local_evidence_count" -lt 1 ]]; then
      fail "$id evidence column must include at least one local evidence path"
    fi
  done < "$MATRIX_FILE"
}

require_file "$MATRIX_FILE" || true

if [[ -f "$MATRIX_FILE" ]]; then
  expected_ids=(
    REQ-404
    REQ-STYLE
    REQ-ADMIN
    REQ-HABIT
    REQ-MINE
    REQ-COUNTDOWN
    REQ-ALMANAC
    REQ-NOTIFY
    REQ-WIDGET
    REQ-DEVICE
  )
  for id in "${expected_ids[@]}"; do
    if [[ "$(grep -Foc "| $id |" "$MATRIX_FILE")" -ne 1 ]]; then
      fail "matrix must contain exactly one row for $id"
    fi
  done

  for group in \
    '1/8 404 and route contracts' \
    '2/8 style layout and readable selection' \
    '3/8 notification ringtone and status progress' \
    '4/8 widgets Android and iOS static contracts' \
    '5/8 admin groups default coins and permissions' \
    '6/8 Flutter analyzer' \
    '7/8 debug APK build' \
    '8/8 device-only notification alarm widget regression'; do
    require_contains "$MATRIX_FILE" "$group" 'goal requirement matrix'
  done

  for marker in \
    'Countdown remains available' \
    'visible add/search/calendar/export/deep-link flow' \
    'Almanac content removes weather' \
    'suitable/avoid in one row' \
    'default soft ringtone' \
    'notification/popup/alarm' \
    'Device readiness must be reported' \
    'both `scripts/validate_device_evidence.sh android` and `scripts/validate_device_evidence.sh ios` must pass' \
    'Passing groups 1-7 is necessary but not sufficient' \
    'Groups `6/8 Flutter analyzer` and `7/8 debug APK build` are full-goal quality/build gates'; do
    require_contains "$MATRIX_FILE" "$marker" 'goal requirement matrix'
  done
  validate_evidence_paths
fi

require_contains "$ROOT_DIR/scripts/validate_goal_closure.sh" 'validate_device_evidence.sh" android' 'goal closure validator'
require_contains "$ROOT_DIR/scripts/validate_goal_closure.sh" 'validate_device_evidence.sh" ios' 'goal closure validator'
require_contains "$ROOT_DIR/scripts/validate_goal_closure.sh" 'generate_device_readiness_report.sh' 'goal closure validator'
require_contains "$ROOT_DIR/scripts/validate_goal_closure.sh" 'validate_device_readiness_report.sh' 'goal closure validator'
require_contains "$ROOT_DIR/scripts/device_regression_check.sh" 'Both Android and iOS evidence must pass' 'device regression gate'
require_contains "$ROOT_DIR/docs/device-regression-evidence.md" 'both Android and iOS device evidence have passed' 'device evidence documentation'
require_contains "$ROOT_DIR/docs/device-regression-evidence.md" 'build/device-readiness/latest' 'device evidence documentation'

if [[ "$failures" -gt 0 ]]; then
  echo "Goal requirement matrix validation failed with $failures issue(s)." >&2
  exit 1
fi

echo "Goal requirement matrix validation passed."
