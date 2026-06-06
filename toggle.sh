#!/usr/bin/env bash
# Toggle emojizasu visibility. Bind this to a key in KDE Settings > Shortcuts > Custom Shortcuts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Lock the focused IC before the picker becomes visible.
# RegisterSelf must happen while the target app's text input is still active.
qdbus6 org.emojizasu.InputMethod /imd org.emojizasu.InputMethod.RegisterSelf 2>/dev/null || true

# If qs is already running, toggle via IPC.
if qs ipc --path "$SCRIPT_DIR/picker" call emojizasu toggle 2>/dev/null; then
    exit 0
fi

# Not running — launch qs, then show once IPC is ready.
qs --path "$SCRIPT_DIR/picker" &
for i in $(seq 1 30); do
    sleep 0.1
    qs ipc --path "$SCRIPT_DIR/picker" call emojizasu open 2>/dev/null && exit 0
done
