#!/usr/bin/env bash
# Runs every harness in sequence. Usage: ./tests/run-all.sh ./openclaw_mini
set -uo pipefail

SRC="${1:-./openclaw_mini}"
DIR="$(cd "$(dirname "$0")" && pwd)"
FAILED=0

for t in test-supervisor test-failure-path test-terminal test-auto-approve test-config-persistence; do
  echo "=============================== $t"
  if "$DIR/$t.sh" "$SRC" 2>&1 | tail -n 3; then
    :
  else
    FAILED=$((FAILED + 1))
    echo "  ^^ $t FAILED"
  fi
done

echo
if [ "$FAILED" -eq 0 ]; then
  echo "All harnesses passed."
else
  echo "$FAILED harness(es) failed."
fi
[ "$FAILED" -eq 0 ]
