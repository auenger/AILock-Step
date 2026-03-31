#!/bin/bash
# on-stop-check.sh — Stop hook
# When Claude is about to stop, check if dev-agent auto-loop should prevent it.
# Exit 2 = block the stop, Claude continues. Exit 0 = allow stop.

BASE="${CLAUDE_PROJECT_DIR:-.}"
QUEUE_FILE="$BASE/feature-workflow/queue.yaml"
CONFIG_FILE="$BASE/feature-workflow/config.yaml"
LOOP_MARKER="$BASE/feature-workflow/.loop-active"

[ -f "$QUEUE_FILE" ] || exit 0
[ -f "$CONFIG_FILE" ] || exit 0

# Determine mode by loop-active marker
if [ -f "$LOOP_MARKER" ]; then
    # Inside /dev-agent auto-loop → only check auto_start_next
    grep -q "auto_start_next: *true" "$CONFIG_FILE" 2>/dev/null || exit 0
else
    # Manual mode (e.g. /new-feature) → check auto_start master switch
    grep -q "auto_start: *true" "$CONFIG_FILE" 2>/dev/null || exit 0
fi

# Check if pending section has entries
PENDING_BLOCK=$(awk '/^pending:/{found=1; next} /^[a-z]/{found=0} found && /- id:/{print}' "$QUEUE_FILE" 2>/dev/null)

if [ -n "$PENDING_BLOCK" ]; then
    echo "[STOP BLOCKED] dev-agent auto-loop active, pending features remain. Continue the loop." >&2
    exit 2
fi

exit 0
