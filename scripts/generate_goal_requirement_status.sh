#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX_FILE="${MATRIX_FILE:-$ROOT_DIR/docs/goal-requirement-matrix.md}"
ALIGNMENT_REPORT_DIR="${ALIGNMENT_REPORT_DIR:-$ROOT_DIR/build/alignment-regression/latest}"
GOAL_REPORT_DIR="${GOAL_REPORT_DIR:-$ROOT_DIR/build/goal-closure/latest}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/goal-requirements/latest}"
ALIGNMENT_SUMMARY="$ALIGNMENT_REPORT_DIR/summary.tsv"
GOAL_SUMMARY="$GOAL_REPORT_DIR/summary.tsv"
OUTPUT_PARENT="$(dirname "$OUTPUT_DIR")"
DEVICE_GROUP='8/8 device-only notification alarm widget regression'
mkdir -p "$OUTPUT_PARENT"
TEMP_OUTPUT_DIR="$(mktemp -d "$OUTPUT_PARENT/.goal-requirements.tmp.XXXXXX")"
STATUS_TSV="$TEMP_OUTPUT_DIR/status.tsv"
STATUS_MD="$TEMP_OUTPUT_DIR/status.md"

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

status_for_group() {
  local group="$1"
  awk -F '\t' -v group="$group" 'NR > 1 && $1 == group { print $2; found = 1 } END { exit found ? 0 : 1 }' "$ALIGNMENT_SUMMARY" || true
}

status_for_check() {
  local check="$1"
  awk -F '\t' -v check="$check" 'NR > 1 && $1 == check { print $2; found = 1 } END { exit found ? 0 : 1 }' "$GOAL_SUMMARY" || true
}

display_status() {
  local status="$1"
  if [[ -n "$status" ]]; then
    printf '%s' "$status"
  else
    printf 'missing'
  fi
}

is_device_backed_requirement() {
  local id="$1"
  [[ "$id" == "REQ-NOTIFY" || "$id" == "REQ-WIDGET" || "$id" == "REQ-DEVICE" ]]
}

device_evidence_passed() {
  [[ "$android_status" == "passed" && "$ios_status" == "passed" ]]
}

device_evidence_reason() {
  local device_group_status="$1"
  printf 'device gate=%s; android_device_evidence=%s; ios_device_evidence=%s' \
    "$(display_status "$device_group_status")" \
    "$(display_status "$android_status")" \
    "$(display_status "$ios_status")"
}

require_file "$MATRIX_FILE" || true
require_file "$ALIGNMENT_SUMMARY" || true
require_file "$GOAL_SUMMARY" || true

if [[ "$failures" -gt 0 ]]; then
  echo "Goal requirement status generation failed with $failures issue(s)." >&2
  exit 1
fi

printf 'id\tstatus\treason\tgroups\trequirement\n' > "$STATUS_TSV"
cat > "$STATUS_MD" <<'MSG'
# Goal Requirement Status

| ID | Status | Reason | Groups | Requirement |
| --- | --- | --- | --- | --- |
MSG

android_status="$(status_for_check android_device_evidence)"
ios_status="$(status_for_check ios_device_evidence)"

while IFS= read -r line; do
  [[ "$line" == \|\ REQ-* ]] || continue

  id="$(printf '%s' "$line" | awk -F '|' '{ gsub(/^ +| +$/, "", $2); print $2 }')"
  requirement="$(printf '%s' "$line" | awk -F '|' '{ gsub(/^ +| +$/, "", $3); print $3 }')"
  groups="$(printf '%s' "$line" | awk -F '|' '{ gsub(/^ +| +$/, "", $4); print $4 }')"
  status="closed"
  reason="all mapped gates passed"
  first_missing_group=""
  first_failed_group=""
  device_group_status=""

  IFS=';' read -ra group_parts <<< "$groups"
  for raw_group in "${group_parts[@]}"; do
    group="$(printf '%s' "$raw_group" | sed -E 's/^ +| +$//g')"
    group_status="$(status_for_group "$group")"
    if [[ "$group" == "$DEVICE_GROUP" ]]; then
      device_group_status="$group_status"
    fi
    if [[ -z "$group_status" ]]; then
      if [[ "$group" != "$DEVICE_GROUP" && -z "$first_missing_group" ]]; then
        first_missing_group="$group"
      fi
      continue
    fi
    if [[ "$group_status" != "passed" ]]; then
      if [[ "$group" != "$DEVICE_GROUP" && -z "$first_failed_group" ]]; then
        first_failed_group="$group is $group_status"
      fi
    fi
  done

  if [[ -n "$first_missing_group" ]]; then
    status="open(gate_missing)"
    reason="mapped gate is missing: $first_missing_group"
  elif [[ -n "$first_failed_group" ]]; then
    status="open(gate_failed)"
    reason="$first_failed_group"
  elif is_device_backed_requirement "$id" && ! device_evidence_passed; then
    status="open(device_evidence)"
    reason="$(device_evidence_reason "$device_group_status")"
  elif is_device_backed_requirement "$id" && [[ -z "$device_group_status" ]]; then
    status="open(gate_missing)"
    reason="mapped gate is missing: $DEVICE_GROUP"
  elif is_device_backed_requirement "$id" && [[ "$device_group_status" != "passed" ]]; then
    status="open(gate_failed)"
    reason="$DEVICE_GROUP is $device_group_status"
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$status" "$reason" "$groups" "$requirement" >> "$STATUS_TSV"
  printf '| %s | %s | %s | %s | %s |\n' "$id" "$status" "$reason" "$groups" "$requirement" >> "$STATUS_MD"
done < "$MATRIX_FILE"

row_count=$(( $(wc -l < "$STATUS_TSV") - 1 ))
if [[ "$row_count" -ne 10 ]]; then
  fail "status.tsv must contain exactly 10 requirement rows, found $row_count"
fi

if [[ "$failures" -gt 0 ]]; then
  rm -rf "$TEMP_OUTPUT_DIR"
  echo "Goal requirement status generation failed with $failures issue(s)." >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mv "$TEMP_OUTPUT_DIR" "$OUTPUT_DIR"
echo "Goal requirement status written to $OUTPUT_DIR"
