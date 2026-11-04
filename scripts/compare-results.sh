#!/bin/bash
# Merge all per-stack CSV summaries into one comparison table.
set -euo pipefail

RESULTS_DIR="$(cd "$(dirname "$0")/.." && pwd)/results"
OUT="$RESULTS_DIR/comparison-$(date -u +"%Y%m%dT%H%M%SZ").csv"

echo "==> Merging results from $RESULTS_DIR..."

# Write header from first summary CSV found
HEADER_WRITTEN=false
> "$OUT"

for f in "$RESULTS_DIR"/*-summary.csv; do
  [ -f "$f" ] || continue
  if [ "$HEADER_WRITTEN" = false ]; then
    head -1 "$f" > "$OUT"
    HEADER_WRITTEN=true
  fi
  tail -n +2 "$f" >> "$OUT"
done

echo ""
echo "==> Comparison table: $OUT"
echo ""
column -t -s',' "$OUT"
