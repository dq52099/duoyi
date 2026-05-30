#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
READINESS_DIR="${READINESS_DIR:-$ROOT_DIR/build/device-readiness/latest}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/device-readiness-missing/latest}"
SUMMARY_TSV="$READINESS_DIR/summary.tsv"
OUTPUT_PARENT="$(dirname "$OUTPUT_DIR")"
mkdir -p "$OUTPUT_PARENT"
TEMP_OUTPUT_DIR="$(mktemp -d "$OUTPUT_PARENT/.device-readiness-missing.tmp.XXXXXX")"
MISSING_TSV="$TEMP_OUTPUT_DIR/missing.tsv"
MISSING_MD="$TEMP_OUTPUT_DIR/missing.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  rm -rf "$TEMP_OUTPUT_DIR"
  exit 1
}

if [[ ! -f "$SUMMARY_TSV" || ! -s "$SUMMARY_TSV" ]]; then
  fail "missing or empty device readiness summary: $SUMMARY_TSV"
fi

printf 'check\tdetail\n' > "$MISSING_TSV"
cat > "$MISSING_MD" <<'MSG'
# Missing Device Readiness

| Check | Detail |
| --- | --- |
MSG

awk -F '\t' 'NR > 1 && $2 == "missing" { print $1 "\t" $3 }' "$SUMMARY_TSV" >> "$MISSING_TSV"
awk -F '\t' 'NR > 1 && $2 == "missing" { printf "| %s | %s |\n", $1, $3 }' "$SUMMARY_TSV" >> "$MISSING_MD"

missing_count=$(( $(wc -l < "$MISSING_TSV") - 1 ))
if [[ "$missing_count" -lt 1 ]]; then
  fail "device readiness has no missing rows; missing summary is not useful"
fi

rm -rf "$OUTPUT_DIR"
mv "$TEMP_OUTPUT_DIR" "$OUTPUT_DIR"
echo "Missing device readiness written to $OUTPUT_DIR"
