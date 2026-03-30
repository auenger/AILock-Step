#!/bin/bash
# on-stop-check.sh — Stop hook
# When Claude is about to stop, check if dev-agent auto-loop should prevent it.
# Exit 1 = block the stop, Claude continues. Exit 0 = allow stop.

QUEUE_FILE="feature-workflow/queue.yaml"
CONFIG_FILE="feature-workflow/config.yaml"

[ -f "$QUEUE_FILE" ] || exit 0
[ -f "$CONFIG_FILE" ] || exit 0

# Check auto_start_next
grep -q "auto_start_next: *true" "$CONFIG_FILE" 2>/dev/null || exit 0

# Check if pending section has entries
PENDING_BLOCK=$(awk '/^pending:/{found=1; next} /^[a-z]/{found=0} found && /- id:/{print}' "$QUEUE_FILE" 2>/dev/null)

if [ -n "$PENDING_BLOCK" ]; then
    echo "[STOP BLOCKED] dev-agent auto-loop active, pending features remain. Continue the loop."
    exit 1
fi

exit 0
