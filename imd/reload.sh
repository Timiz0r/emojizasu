#!/usr/bin/env bash
set -e
# Reload fcitx5 (and the emojizasu addon) on KDE Plasma Wayland WITHOUT the
# "Fcitx should be launched by KWin" warning.
#
# That warning appears when a fresh `fcitx5` starts outside KWin's launcher and
# so can't bind the zwp_input_method_v2 global (waylandim then doesn't work).
# Instead of launching fcitx5 ourselves, toggle KWin's virtual keyboard: KWin
# tears down and relaunches `fcitx5-wayland-launcher --reopen`, which relaunches
# fcitx5 with the proper Wayland frontend. The relaunched fcitx5 inherits
# FCITX_ADDON_DIRS from KWin's environment (set at login via environment.d), so
# the addon is found.
#
# Note: `fcitx5-remote -e`/`-r` is NOT enough — it stops fcitx5 but the launcher
# does not reliably respawn it. The KWin toggle is what reliably works.

QDBUS="$(command -v qdbus6 || command -v qdbus)"
VK=(org.kde.KWin /VirtualKeyboard org.kde.kwin.VirtualKeyboard.enabled)

"$QDBUS" "${VK[@]}" false
sleep 1
"$QDBUS" "${VK[@]}" true
sleep 2

if pgrep -x fcitx5 >/dev/null; then
    echo "fcitx5 reloaded via KWin (pid $(pgrep -x fcitx5 | head -1))."
else
    echo "WARNING: fcitx5 not running after toggle — check 'qdbus6 org.kde.KWin /VirtualKeyboard'." >&2
    exit 1
fi
