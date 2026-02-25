#!/bin/bash
# Requires: CURSOR_API_KEY env var set
MAX_ITERATIONS=${1:-20}
PROMPT_FILE="${2:-PROMPT_build.md}"
ITERATION=0
COMPLETE=false

if [ -z "$CURSOR_API_KEY" ]; then
  echo "Error: CURSOR_API_KEY is not set."
  exit 1
fi

echo "Starting ralph loop (cursor): max=$MAX_ITERATIONS prompt=$PROMPT_FILE"

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
  ITERATION=$((ITERATION + 1))
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo ""
  echo "=== [$TIMESTAMP] Iteration $ITERATION / $MAX_ITERATIONS ==="

  OUTPUT=$(agent -p --force "$(cat "$PROMPT_FILE")" 2>&1)

  {
    echo ""
    echo "--- iteration $ITERATION ($TIMESTAMP) ---"
    echo "$OUTPUT"
  } >> progress.txt

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo "Completion promise received. Loop complete after $ITERATION iterations."
    COMPLETE=true
    break
  fi

  echo "No completion signal. Continuing..."
  sleep 2
done

if [ "$COMPLETE" = false ]; then
  echo ""
  echo "Max iterations ($MAX_ITERATIONS) reached without completion."
  echo "Task state preserved in prd.json. Review progress.txt for context."
  echo "Re-run to continue."
  exit 1
fi

exit 0
