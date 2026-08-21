#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

# Installs into ~/.local. fcitx5 finds the addon .so via FCITX_ADDON_DIRS
# (which replaces its compiled-in default, so /usr/lib/fcitx5 must stay in the
# list or other addons like waylandim won't load). The .conf goes under
# XDG_DATA_HOME, which fcitx5 already searches for addon configs.

LIB_DIR="$HOME/.local/lib/fcitx5"
CONF_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/addon"
ADDON_DIRS="$LIB_DIR:/usr/lib/fcitx5"

cargo build --release
install -Dm755 "target/release/libemojizasu_imd.so" "$LIB_DIR/libemojizasu_imd.so"
install -Dm644 "emojizasu-imd.conf"                 "$CONF_DIR/emojizasu-imd.conf"

# Older installers placed the isolated test addon alongside production. Loading
# both into one fcitx5 process causes their exported native symbols to collide.
rm -f "$LIB_DIR/libemojizasu_imd_test.so" "$CONF_DIR/emojizasu-imd-test.conf"

# Persist FCITX_ADDON_DIRS for the daily-driver session (applies next login).
ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"
install -d "$ENV_DIR"
printf 'FCITX_ADDON_DIRS=%s\n' "$ADDON_DIRS" > "$ENV_DIR/emojizasu.conf"

echo "Install complete."
echo
echo "Wrote $ENV_DIR/emojizasu.conf:"
echo "  FCITX_ADDON_DIRS=$ADDON_DIRS"
echo
echo "FIRST install: log out and back in once so KWin (and the fcitx5 it"
echo "launches) inherit FCITX_ADDON_DIRS from the session environment."
echo
echo "AFTER that, to reload a rebuilt addon WITHOUT the 'should be launched by"
echo "KWin' warning, do NOT run fcitx5 directly. Restart it via KWin's launcher:"
echo "  ./reload.sh"
echo
echo "(Tests/CI export FCITX_ADDON_DIRS and launch their own fcitx5 directly.)"
