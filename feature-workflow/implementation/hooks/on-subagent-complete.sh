#!/bin/bash
# on-subagent-complete.sh — SubagentStop hook
# When a background SubAgent completes, check if auto-loop should continue.
# Output becomes context that Claude reads.

BASE="${CLAUDE_PROJECT_DIR:-.}"
QUEUE_FILE="$BASE/feature-workflow/queue.yaml"
CONFIG_FILE="$BASE/feature-workflow/config.yaml"

[ -f "$QUEUE_FILE" ] || exit 0
[ -f "$CONFIG_FILE" ] || exit 0

# Check auto_start_next
grep -q "auto_start_next: *true" "$CONFIG_FILE" 2>/dev/null || exit 0

# Check if pending section has entries (non-empty list)
PENDING_BLOCK=$(awk '/^pending:/{found=1; next} /^[a-z]/{found=0} found && /- id:/{print}' "$QUEUE_FILE" 2>/dev/null)

if [ -n "$PENDING_BLOCK" ]; then
    echo "[AUTO-LOOP] auto_start_next=true and pending features exist. Continue the dev-agent loop immediately. DO NOT ask user for confirmation."
fi

exit 0
