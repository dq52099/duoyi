#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TOOL_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MATRIX_FILE="${MATRIX_FILE:-$ROOT_DIR/docs/goal-requirement-matrix.md}"
REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/build/alignment-regression/latest}"
GOAL_REPORT_DIR="${GOAL_REPORT_DIR:-$ROOT_DIR/build/goal-closure/latest}"
STATUS_DIR="${STATUS_DIR:-$ROOT_DIR/build/goal-requirements/latest}"
SUMMARY_TSV="$REPORT_DIR/summary.tsv"
GOAL_SUMMARY_TSV="$GOAL_REPORT_DIR/summary.tsv"
GOAL_SUMMARY_MD="$GOAL_REPORT_DIR/summary.md"
DEVICE_READINESS_DIR="${DEVICE_READINESS_DIR:-$(dirname "$GOAL_REPORT_DIR")/device-readiness}"
DEVICE_READINESS_MISSING_DIR="${DEVICE_READINESS_MISSING_DIR:-$(dirname "$GOAL_REPORT_DIR")/device-readiness-missing}"
failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

run_check() {
  local name="$1"
  local log_name="$2"
  shift 2
  local log_file="$GOAL_REPORT_DIR/$log_name"
  local status="passed"
  local exit_code=0

  set +e
  "$@" > "$log_file" 2>&1
  exit_code=$?
  set -e
  if [[ "$exit_code" -ne 0 ]]; then
    status="failed($exit_code)"
  fi
  printf '%s\t%s\t%s\n' "$name" "$status" "$log_file" >> "$GOAL_SUMMARY_TSV"
  printf '| %s | %s | `%s` |\n' "$name" "$status" "$log_file" >> "$GOAL_SUMMARY_MD"
  printf '%s: %s\n' "$name" "$status"
  return "$exit_code"
}

check_alignment_gates_passed() {
  if [[ ! -f "$SUMMARY_TSV" ]]; then
    echo "alignment summary is missing: $SUMMARY_TSV" >&2
    return 1
  fi
  awk -F '\t' 'NR > 1 && $2 != "passed" {
    printf "%s is not closed: %s\n", $1, $2
    failed = 1
  } END { exit failed ? 1 : 0 }' "$SUMMARY_TSV"
}

check_alignment_report_freshness() {
  if [[ ! -f "$SUMMARY_TSV" ]]; then
    echo "alignment summary is missing: $SUMMARY_TSV" >&2
    return 1
  fi

  # Appending expanded gates must not renew the eight original gate results.
  # Keep the oldest existing bound; optional logs do not define legacy freshness.
  local freshness_reference="$SUMMARY_TSV" legacy_log group
  local legacy_groups=(
    '1/8 404 and route contracts'
    '2/8 style layout and readable selection'
    '3/8 notification ringtone and status progress'
    '4/8 widgets Android and iOS static contracts'
    '5/8 admin groups default coins and permissions'
    '6/8 Flutter analyzer'
    '7/8 debug APK build'
    '8/8 device-only notification alarm widget regression'
  )
  for group in "${legacy_groups[@]}"; do
    if ! legacy_log="$(awk -F '\t' -v group="$group" '
      NR > 1 && $1 == group { count++; path = $4 }
      END { if (count != 1) exit 1; print path }
    ' "$SUMMARY_TSV")" || [[ ! -f "$legacy_log" || ! -r "$legacy_log" || ! -s "$legacy_log" ]]; then
      echo "alignment report freshness could not be verified: missing or invalid legacy log for $group" >&2
      return 1
    fi
    if [[ "$legacy_log" -ot "$freshness_reference" ]]; then
      freshness_reference="$legacy_log"
    fi
  done

  local stale_files
  if ! stale_files="$(
    find \
      "$ROOT_DIR/android" \
      "$ROOT_DIR/backend" \
      "$ROOT_DIR/docs" \
      "$ROOT_DIR/ios" \
      "$ROOT_DIR/lib" \
      "$ROOT_DIR/scripts" \
      "$ROOT_DIR/test" \
      "$ROOT_DIR/pubspec.yaml" \
      "$ROOT_DIR/pubspec.lock" \
      \( -path "$ROOT_DIR/backend/backups" \
         -o -path "$ROOT_DIR/backend/uploads" \) -prune -o \
      -type f -newer "$freshness_reference" \
      ! -path "$ROOT_DIR/backend/duoyi.db" \
      ! -path "$ROOT_DIR/backend/duoyi.db-wal" \
      ! -path "$ROOT_DIR/backend/duoyi.db-shm" \
      ! -path "$ROOT_DIR/backend/duoyi.db-journal" \
      ! -path "$ROOT_DIR/backend/fingertip_time.db" \
      ! -path "$ROOT_DIR/backend/fingertip_time.db-wal" \
      ! -path "$ROOT_DIR/backend/fingertip_time.db-shm" \
      ! -path "$ROOT_DIR/backend/fingertip_time.db-journal" \
      ! -path "$ROOT_DIR/build/*" \
      ! -path "$ROOT_DIR/.dart_tool/*" \
      ! -path "$ROOT_DIR/.git/*" \
      ! -path "$ROOT_DIR/android/.gradle/*" \
      ! -path "$ROOT_DIR/android/build/*" \
      ! -path "$ROOT_DIR/android/app/build/*" \
      ! -path '*/__pycache__/*' \
      ! -name '*.pyc' \
      -print \
      | sort \
      | sed -n '1,20p'
  )"; then
    echo "alignment report freshness could not be verified: source scan failed" >&2
    return 1
  fi
  if [[ -n "$stale_files" ]]; then
    {
      echo "alignment regression report is stale; rerun scripts/alignment_regression_gate.sh first"
      echo "files newer than legacy freshness reference $freshness_reference:"
      printf '%s\n' "$stale_files"
    } >&2
    return 1
  fi
}

# A well-formed status report can legitimately contain open requirements. It
# proves completion only when every requirement is closed, including the four
# expanded acceptance groups that are separate from the eight legacy gates.
check_all_requirements_closed() {
  local status_file="$STATUS_DIR/status.tsv"
  if [[ ! -s "$status_file" ]]; then
    echo "requirement status is missing: $status_file" >&2
    return 1
  fi
  awk -F '\t' '
    NR == 1 {
      if ($0 != "id\tstatus\treason\tgroups\trequirement") {
        print "requirement status header is invalid"
        failed = 1
      }
      next
    }
    $2 != "closed" {
      printf "%s is not closed: %s (%s)\n", $1, $2, $3
      failed = 1
    }
    END {
      if (NR != 15) {
        print "requirement status must contain exactly 14 requirement rows"
        failed = 1
      }
      exit failed ? 1 : 0
    }
  ' "$status_file"
}

rm -rf "$GOAL_REPORT_DIR"
mkdir -p "$GOAL_REPORT_DIR"
printf 'check\tstatus\tlog\n' > "$GOAL_SUMMARY_TSV"
cat > "$GOAL_SUMMARY_MD" <<'MSG'
# Goal Closure Validation

| Check | Status | Log |
| --- | --- | --- |
MSG

if ! run_check 'alignment_report' 'alignment_report.log' env REPORT_DIR="$REPORT_DIR" "$TOOL_ROOT_DIR/scripts/validate_alignment_report.sh"; then
  fail "alignment regression report is incomplete or malformed"
fi

if ! run_check 'alignment_gates_passed' 'alignment_gates_passed.log' check_alignment_gates_passed; then
  fail "one or more alignment regression gates are not closed"
fi

if ! run_check 'alignment_report_freshness' 'alignment_report_freshness.log' check_alignment_report_freshness; then
  fail "alignment regression report is stale"
fi

if ! run_check 'goal_requirement_matrix' 'goal_requirement_matrix.log' env MATRIX_FILE="$MATRIX_FILE" "$TOOL_ROOT_DIR/scripts/validate_goal_requirement_matrix.sh"; then
  fail "goal requirement matrix is incomplete or malformed"
fi

if ! run_check 'device_readiness' 'device_readiness.log' env OUTPUT_DIR="$DEVICE_READINESS_DIR" "$TOOL_ROOT_DIR/scripts/generate_device_readiness_report.sh"; then
  fail "device readiness report could not be generated"
fi

if ! run_check 'device_readiness_validation' 'device_readiness_validation.log' env REPORT_DIR="$DEVICE_READINESS_DIR" "$TOOL_ROOT_DIR/scripts/validate_device_readiness_report.sh"; then
  fail "device readiness report is incomplete or malformed"
fi

if ! run_check 'device_readiness_missing' 'device_readiness_missing.log' env READINESS_DIR="$DEVICE_READINESS_DIR" OUTPUT_DIR="$DEVICE_READINESS_MISSING_DIR" "$TOOL_ROOT_DIR/scripts/summarize_device_readiness_missing.sh"; then
  fail "missing device readiness summary could not be generated"
fi

if ! run_check 'device_readiness_missing_validation' 'device_readiness_missing_validation.log' env REPORT_DIR="$DEVICE_READINESS_MISSING_DIR" "$TOOL_ROOT_DIR/scripts/validate_device_readiness_missing.sh"; then
  fail "missing device readiness summary is incomplete or malformed"
fi

if [[ -f "$SUMMARY_TSV" ]]; then
  while IFS=$'\t' read -r group status duration log_path; do
    [[ "$group" == "group" ]] && continue
    if [[ "$status" != "passed" ]]; then
      fail "$group is not closed: $status"
    fi
  done < "$SUMMARY_TSV"
else
  fail "alignment summary is missing: $SUMMARY_TSV"
fi

if ! run_check 'android_device_evidence' 'android_device_evidence.log' "$TOOL_ROOT_DIR/scripts/validate_device_evidence.sh" android; then
  fail "Android device evidence is incomplete"
fi

if ! run_check 'ios_device_evidence' 'ios_device_evidence.log' "$TOOL_ROOT_DIR/scripts/validate_device_evidence.sh" ios; then
  fail "iOS device evidence is incomplete"
fi

if ! run_check 'goal_requirement_status' 'goal_requirement_status.log' env MATRIX_FILE="$MATRIX_FILE" REPORT_DIR="$REPORT_DIR" ALIGNMENT_REPORT_DIR="$REPORT_DIR" GOAL_REPORT_DIR="$GOAL_REPORT_DIR" STATUS_DIR="$STATUS_DIR" OUTPUT_DIR="$STATUS_DIR" "$TOOL_ROOT_DIR/scripts/generate_goal_requirement_status.sh"; then
  fail "goal requirement status report could not be generated"
fi

if ! run_check 'goal_requirement_status_validation' 'goal_requirement_status_validation.log' env REPORT_DIR="$REPORT_DIR" GOAL_REPORT_DIR="$GOAL_REPORT_DIR" STATUS_DIR="$STATUS_DIR" "$TOOL_ROOT_DIR/scripts/validate_goal_requirement_status.sh"; then
  fail "goal requirement status report is incomplete or malformed"
fi

if ! run_check 'all_requirements_closed' 'all_requirements_closed.log' check_all_requirements_closed; then
  fail "goal requirements remain open; a valid status report is not proof of completion"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Goal closure validation failed with $failures issue(s). Report written to $GOAL_REPORT_DIR" >&2
  exit 1
fi

echo "Goal closure validation passed. Report written to $GOAL_REPORT_DIR"
