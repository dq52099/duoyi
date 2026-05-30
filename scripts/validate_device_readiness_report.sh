#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/build/device-readiness/latest}"
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

expected_checks=(
  host_architecture
  android_runtime
  ios_runtime
  adb_device
  android_emulator_binary
  android_emulator_package
  android_avd
  android_system_images
  kvm
  android_emulator_launchability
  ios_host
)

if [[ -f "$SUMMARY_TSV" ]]; then
  header="$(head -n 1 "$SUMMARY_TSV")"
  if [[ "$header" != $'check\tstatus\tdetail' ]]; then
    fail "summary.tsv header is invalid"
  fi

  for check in "${expected_checks[@]}"; do
    count="$(awk -F '\t' -v check="$check" 'NR > 1 && $1 == check { count++ } END { print count + 0 }' "$SUMMARY_TSV")"
    if [[ "$count" -ne 1 ]]; then
      fail "summary.tsv must contain exactly one row for $check, found $count"
    fi
  done

  while IFS=$'\t' read -r check status detail extra; do
    [[ "$check" == "check" ]] && continue
    if [[ -n "${extra:-}" ]]; then
      fail "summary.tsv row has too many columns for $check"
    fi
    if [[ ! "$status" =~ ^(ready|available|missing)$ ]]; then
      fail "invalid status for $check: $status"
    fi
    if [[ -z "$detail" ]]; then
      fail "empty detail for $check"
    fi
  done < "$SUMMARY_TSV"
fi

if [[ -f "$SUMMARY_MD" ]]; then
  for marker in 'Device Readiness Report' 'host_architecture' 'android_runtime' 'android_emulator_launchability' 'ios_host'; do
    if ! grep -Fq "$marker" "$SUMMARY_MD"; then
      fail "summary.md missing marker: $marker"
    fi
  done
fi

for artifact in flutter_devices.txt flutter_devices_machine.json adb_devices.txt sdkmanager_list.txt avd_list.txt host_uname.txt; do
  require_file "$REPORT_DIR/$artifact" || true
done

if [[ "$failures" -gt 0 ]]; then
  echo "Device readiness report validation failed with $failures issue(s)." >&2
  exit 1
fi

echo "Device readiness report validation passed."
