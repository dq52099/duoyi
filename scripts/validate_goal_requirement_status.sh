#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS_DIR="${STATUS_DIR:-$ROOT_DIR/build/goal-requirements/latest}"
REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/build/alignment-regression/latest}"
GOAL_REPORT_DIR="${GOAL_REPORT_DIR:-$ROOT_DIR/build/goal-closure/latest}"
STATUS_TSV="$STATUS_DIR/status.tsv"
STATUS_MD="$STATUS_DIR/status.md"
ALIGNMENT_SUMMARY="$REPORT_DIR/summary.tsv"
GOAL_SUMMARY="$GOAL_REPORT_DIR/summary.tsv"
DEVICE_GROUP='8/8 device-only notification alarm widget regression'
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

require_file "$STATUS_TSV" || true
require_file "$STATUS_MD" || true

status_for_group() {
  local group="$1"
  [[ -f "$ALIGNMENT_SUMMARY" ]] || return 1
  awk -F '\t' -v group="$group" 'NR > 1 && $1 == group { print $2; found = 1 } END { exit found ? 0 : 1 }' "$ALIGNMENT_SUMMARY"
}

status_for_check() {
  local check="$1"
  [[ -f "$GOAL_SUMMARY" ]] || return 1
  awk -F '\t' -v check="$check" 'NR > 1 && $1 == check { print $2; found = 1 } END { exit found ? 0 : 1 }' "$GOAL_SUMMARY"
}

status_for_requirement() {
  local id="$1"
  awk -F '\t' -v id="$id" 'NR > 1 && $1 == id { print $2; found = 1 } END { exit found ? 0 : 1 }' "$STATUS_TSV"
}

reason_for_requirement() {
  local id="$1"
  awk -F '\t' -v id="$id" 'NR > 1 && $1 == id { print $3; found = 1 } END { exit found ? 0 : 1 }' "$STATUS_TSV"
}

device_evidence_is_missing() {
  local android_status=""
  local ios_status=""
  android_status="$(status_for_check android_device_evidence || true)"
  ios_status="$(status_for_check ios_device_evidence || true)"
  [[ "$android_status" != "passed" || "$ios_status" != "passed" ]]
}

groups_one_to_seven_passed() {
  local group=""
  local status=""
  local groups=(
    '1/8 404 and route contracts'
    '2/8 style layout and readable selection'
    '3/8 notification ringtone and status progress'
    '4/8 widgets Android and iOS static contracts'
    '5/8 admin groups default coins and permissions'
    '6/8 Flutter analyzer'
    '7/8 debug APK build'
  )

  [[ -f "$ALIGNMENT_SUMMARY" ]] || return 1
  for group in "${groups[@]}"; do
    status="$(status_for_group "$group" || true)"
    [[ "$status" == "passed" ]] || return 1
  done
  return 0
}

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

if [[ -f "$STATUS_TSV" ]]; then
  header="$(head -n 1 "$STATUS_TSV")"
  if [[ "$header" != $'id\tstatus\treason\tgroups\trequirement' ]]; then
    fail "status.tsv header is invalid"
  fi

  row_count=$(( $(wc -l < "$STATUS_TSV") - 1 ))
  if [[ "$row_count" -ne 10 ]]; then
    fail "status.tsv must contain exactly 10 requirement rows, found $row_count"
  fi

  for id in "${expected_ids[@]}"; do
    count="$(awk -F '\t' -v id="$id" 'NR > 1 && $1 == id { count++ } END { print count + 0 }' "$STATUS_TSV")"
    if [[ "$count" -ne 1 ]]; then
      fail "status.tsv must contain exactly one row for $id, found $count"
    fi
  done

  while IFS=$'\t' read -r id status reason groups requirement extra; do
    [[ "$id" == "id" ]] && continue
    if [[ -n "${extra:-}" ]]; then
      fail "status.tsv row has too many columns for $id"
    fi
    if [[ ! "$status" =~ ^(closed|open\((gate_failed|gate_missing|device_evidence)\))$ ]]; then
      fail "invalid status for $id: $status"
    fi
    if [[ -z "$reason" || -z "$groups" || -z "$requirement" ]]; then
      fail "status.tsv row has empty fields for $id"
    fi
  done < "$STATUS_TSV"

  if [[ -f "$GOAL_SUMMARY" ]] && groups_one_to_seven_passed && device_evidence_is_missing; then
    for id in REQ-NOTIFY REQ-WIDGET REQ-DEVICE; do
      status="$(status_for_requirement "$id" || true)"
      reason="$(reason_for_requirement "$id" || true)"
      if [[ "$status" != "open(device_evidence)" ]]; then
        fail "$id must stay open(device_evidence) until Android and iOS device evidence pass, found $status"
      fi
      if [[ "$reason" != *'android_device_evidence='* || "$reason" != *'ios_device_evidence='* ]]; then
        fail "$id device evidence reason must include Android and iOS evidence statuses"
      fi
    done
  fi

  if groups_one_to_seven_passed; then
    device_group_status="$(status_for_group "$DEVICE_GROUP" || true)"
    if [[ "$device_group_status" != "passed" ]]; then
      for id in REQ-404 REQ-STYLE REQ-ADMIN REQ-HABIT REQ-MINE REQ-COUNTDOWN REQ-ALMANAC; do
        status="$(status_for_requirement "$id" || true)"
        if [[ "$status" != "closed" ]]; then
          fail "$id should be closed when groups 1-7 pass and it does not require device evidence, found $status"
        fi
      done
      for id in REQ-NOTIFY REQ-WIDGET REQ-DEVICE; do
        status="$(status_for_requirement "$id" || true)"
        if [[ "$status" == "closed" ]]; then
          fail "$id must not close while $DEVICE_GROUP is $device_group_status"
        fi
      done
    fi
  fi
fi

if [[ -f "$STATUS_MD" ]]; then
  for marker in 'Goal Requirement Status' 'REQ-404' 'REQ-DEVICE'; do
    if ! grep -Fq "$marker" "$STATUS_MD"; then
      fail "status.md missing marker: $marker"
    fi
  done
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Goal requirement status validation failed with $failures issue(s)." >&2
  exit 1
fi

echo "Goal requirement status validation passed."
