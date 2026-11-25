#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/build/alignment-regression/latest}"
SUMMARY_TSV="$REPORT_DIR/summary.tsv"
SUMMARY_MD="$REPORT_DIR/summary.md"
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

require_file "$SUMMARY_TSV" || true
require_file "$SUMMARY_MD" || true

if [[ -f "$SUMMARY_TSV" ]]; then
  header="$(head -n 1 "$SUMMARY_TSV")"
  if [[ "$header" != $'group\tstatus\tduration_seconds\tlog' ]]; then
    fail "summary.tsv header is invalid"
  fi

  expected_groups=(
    '1/8 404 and route contracts'
    '2/8 style layout and readable selection'
    '3/8 notification ringtone and status progress'
    '4/8 widgets Android and iOS static contracts'
    '5/8 admin groups default coins and permissions'
    '6/8 Flutter analyzer'
    '7/8 debug APK build'
    '8/8 device-only notification alarm widget regression'
  )

  optional_groups=(
    'default iOS visual acceptance'
    'global localization acceptance'
    'settings flow acceptance'
    'mobile performance acceptance'
  )

  for group in "${expected_groups[@]}"; do
    count="$(awk -F '\t' -v group="$group" 'NR > 1 && $1 == group { count++ } END { print count + 0 }' "$SUMMARY_TSV")"
    if [[ "$count" -eq 0 ]]; then
      fail "summary.tsv missing group: $group"
    fi
  done

  while IFS= read -r duplicate; do
    [[ -z "$duplicate" ]] || fail "summary.tsv duplicate group: $duplicate"
  done < <(awk -F '\t' 'NR > 1 { count[$1]++ } END { for (group in count) if (count[group] > 1) print group }' "$SUMMARY_TSV")

  if ! awk -F '\t' 'NR > 1 && NF != 4 { bad = 1 } END { exit bad ? 1 : 0 }' "$SUMMARY_TSV"; then
    fail "summary.tsv rows must have exactly four columns"
  fi

  row_number=0
  while IFS=$'\t' read -r group status duration log_path || [[ -n "$group$status$duration$log_path" ]]; do
    row_number=$((row_number + 1))
    [[ "$row_number" -eq 1 ]] && continue
    known=0
    for allowed in "${expected_groups[@]}" "${optional_groups[@]}"; do
      [[ "$group" != "$allowed" ]] || known=1
    done
    [[ "$known" -eq 1 ]] || fail "summary.tsv unknown group: $group"
    if [[ ! "$status" =~ ^(passed|failed\([0-9]+\))$ ]]; then
      fail "invalid status for $group: $status"
    fi
    if [[ ! "$duration" =~ ^[0-9]+$ ]]; then
      fail "invalid duration for $group: $duration"
    fi
    if [[ -z "$log_path" ]]; then
      fail "missing log path for $group"
    else
      require_file "$log_path" || true
    fi
  done < "$SUMMARY_TSV"
fi

if [[ -f "$SUMMARY_MD" ]]; then
  for marker in 'Alignment Regression Gate' '1/8 404 and route contracts' '8/8 device-only notification alarm widget regression'; do
    if ! grep -Fq "$marker" "$SUMMARY_MD"; then
      fail "summary.md missing marker: $marker"
    fi
  done
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Alignment report validation failed with $failures issue(s)." >&2
  exit 1
fi

echo "Alignment report validation passed."
