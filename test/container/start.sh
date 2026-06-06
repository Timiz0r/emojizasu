#!/usr/bin/env bash

# Layout expected at runtime (mounted by the host launcher / compose):
#   /src                       the repo (read-only is fine)
#   /addon/libemojizasu_imd_test.so   host-built test-variant addon
set -u

ADDON_SO="${TEST_ADDON_SO:-/addon/libemojizasu_imd_test.so}"
ADDON_CONF="${EMZ_ADDON_CONF:-/src/imd/emojizasu-imd-test.conf}"
SERVICE="org.emojizasu.InputMethodTest"
TARGET_DIR="/src/test/target"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
export QT_QPA_PLATFORM=wayland
export QT_QUICK_BACKEND=software      # no GPU → software scene graph, no GL
export LIBGL_ALWAYS_SOFTWARE=1
export EMOJIZASU_RECENT_FILE="$(mktemp /tmp/emojizasu-recent.XXXXXX)"

log() { echo "[setup] $*"; }
die() { echo "[setup] FATAL: $*" >&2; exit 1; }

eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
trap 'kill "$DBUS_SESSION_BUS_PID" 2>/dev/null; pkill -x sway 2>/dev/null; pkill -x fcitx5 2>/dev/null' EXIT
log "session bus: $DBUS_SESSION_BUS_ADDRESS"

cat > /tmp/sway.cfg <<EOF
output HEADLESS-1 resolution 1280x720
xwayland disable
# No bars/bg/exec — the test launches its own clients.
EOF
sway -c /tmp/sway.cfg >/tmp/sway.log 2>&1 &
for i in $(seq 1 80); do
    SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)
    [ -n "${SWAYSOCK:-}" ] && break; sleep 0.25
done
[ -n "${SWAYSOCK:-}" ] || { echo "[setup] sway never came up:"; tail -20 /tmp/sway.log; exit 1; }
export SWAYSOCK

for i in $(seq 1 40); do
    WAYLAND_DISPLAY=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' -printf '%f\n' 2>/dev/null | head -1)
    [ -n "${WAYLAND_DISPLAY:-}" ] && break; sleep 0.1
done
export WAYLAND_DISPLAY
log "sway up: SWAYSOCK=$SWAYSOCK WAYLAND_DISPLAY=$WAYLAND_DISPLAY"

[ -f "$ADDON_SO" ]   || die "addon .so not mounted at $ADDON_SO"
[ -f "$ADDON_CONF" ] || die "addon .conf not found at $ADDON_CONF"
install -Dm755 "$ADDON_SO"   /usr/lib/fcitx5/libemojizasu_imd_test.so
install -Dm644 "$ADDON_CONF" /usr/share/fcitx5/addon/emojizasu-imd-test.conf
# ABI sanity: every needed lib must resolve in this image.
if ldd /usr/lib/fcitx5/libemojizasu_imd_test.so 2>/dev/null | grep -qi "not found"; then
    echo "[setup] ABI ERROR — unresolved libraries (host/container fcitx5 mismatch?):"
    ldd /usr/lib/fcitx5/libemojizasu_imd_test.so | grep -i "not found"
    exit 1
fi
log "addon installed; libs resolve"

fcitx5 >/tmp/fcitx5.log 2>&1 &
for i in $(seq 1 160); do
    qdbus6 "$SERVICE" /imd "$SERVICE.GetRecent" >/dev/null 2>&1 && break
    sleep 0.25
done
if ! qdbus6 "$SERVICE" /imd "$SERVICE.GetRecent" >/dev/null 2>&1; then
    echo "[setup] $SERVICE never came up. fcitx5 log:"; tail -25 /tmp/fcitx5.log
    echo "--- did the addon load? ---"; grep -i "emojizasu\|addon" /tmp/fcitx5.log | tail -10
    exit 1
fi
log "fcitx5 up; $SERVICE ready"

export TEST_COMPOSITOR=sway
[ "$#" -gt 0 ] || set -- bash /src/test/tests.sh
log "exec: $*"
exec "$@"
