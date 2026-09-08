#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

# Installs into ~/.local. fcitx5 finds the addon .so via FCITX_ADDON_DIRS
# (which replaces its compiled-in default, so the system addon dir must stay in
# the list or other addons like waylandim won't load). The .conf goes under
# XDG_DATA_HOME, which fcitx5 already searches for addon configs.

LIB_DIR="$HOME/.local/lib/fcitx5"
CONF_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/addon"

# The system addon dir is NOT always /usr/lib/fcitx5: Debian/Ubuntu put it under
# a multiarch libdir (e.g. /usr/lib/x86_64-linux-gnu/fcitx5). Hardcoding the
# wrong path silently drops every stock addon, so resolve it instead.
# libwaylandim.so is the marker, since fcitx5 is useless on Wayland without it.
find_system_addon_dir() {
    local candidates=() d
    if command -v pkg-config >/dev/null; then
        d="$(pkg-config --variable=libdir Fcitx5Core 2>/dev/null || true)"
        [ -n "$d" ] && candidates+=("$d/fcitx5")
    fi
    candidates+=(
        /usr/lib/fcitx5
        "/usr/lib/$(uname -m)-linux-gnu/fcitx5"
        /usr/lib64/fcitx5
        /usr/local/lib/fcitx5
    )
    for d in "${candidates[@]}"; do
        [ -e "$d/libwaylandim.so" ] && { echo "$d"; return 0; }
    done
    for d in "${candidates[@]}"; do
        [ -d "$d" ] && { echo "$d"; return 0; }
    done
    return 1
}

if ! SYSTEM_ADDON_DIR="${SYSTEM_ADDON_DIR:-$(find_system_addon_dir)}"; then
    echo "ERROR: could not locate the system fcitx5 addon directory." >&2
    echo "Is fcitx5 installed? Set SYSTEM_ADDON_DIR manually and re-run." >&2
    exit 1
fi

ADDON_DIRS="$LIB_DIR:$SYSTEM_ADDON_DIR"

cargo build --release
install -Dm755 "target/release/libemojizasu_imd.so" "$LIB_DIR/libemojizasu_imd.so"
install -Dm644 "emojizasu-imd.conf"                 "$CONF_DIR/emojizasu-imd.conf"

# Older installers placed the isolated test addon alongside production. Loading
# both into one fcitx5 process causes their exported native symbols to collide.
rm -f "$LIB_DIR/libemojizasu_imd_test.so" "$CONF_DIR/emojizasu-imd-test.conf"

# Persist FCITX_ADDON_DIRS for future sessions (applies from next login on).
ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"
install -d "$ENV_DIR"
printf 'FCITX_ADDON_DIRS=%s\n' "$ADDON_DIRS" > "$ENV_DIR/emojizasu.conf"

# environment.d is only read at login, so also push the value into the running
# systemd user manager. Anything it spawns from here on (fcitx5 included)
# inherits it, which is what makes this install usable without logging out.
if command -v systemctl >/dev/null; then
    systemctl --user set-environment "FCITX_ADDON_DIRS=$ADDON_DIRS" 2>/dev/null || true
fi

# Restarting fcitx5 is mandatory: addons are only loaded at startup, so a fresh
# install (or a rebuilt .so) does nothing until the daemon comes back up.
reload_fcitx5() {
    export FCITX_ADDON_DIRS="$ADDON_DIRS"

    # On KDE, fcitx5 must be respawned by KWin's launcher or waylandim can't bind
    # zwp_input_method_v2 ("Fcitx should be launched by KWin"). reload.sh does that.
    case "${XDG_CURRENT_DESKTOP,,}" in
        *kde*|*plasma*) ./reload.sh; return $? ;;
    esac

    # Everywhere else (niri and other wlroots-style compositors) fcitx5 can simply
    # replace itself in place.
    command -v fcitx5 >/dev/null || return 1
    setsid fcitx5 -r -d >/dev/null 2>&1 || true
}

echo
echo "Wrote $ENV_DIR/emojizasu.conf:"
echo "  FCITX_ADDON_DIRS=$ADDON_DIRS"
echo
echo "Reloading fcitx5..."

RELOADED=0
reload_fcitx5 && RELOADED=1

# Confirm the addon actually loaded rather than assuming the restart worked.
LOADED=0
if [ "$RELOADED" = 1 ] && command -v busctl >/dev/null; then
    for _ in $(seq 1 20); do
        sleep 0.5
        if busctl --user list 2>/dev/null | grep -q "org.emojizasu.InputMethod"; then
            LOADED=1
            break
        fi
    done
fi

echo
if [ "$LOADED" != 1 ]; then
    echo "Install complete, but the addon did not come up on D-Bus."
    echo
    echo "Try logging out and back in once, so the session (and the fcitx5 it"
    echo "launches) inherits FCITX_ADDON_DIRS from $ENV_DIR/emojizasu.conf."
    echo
    echo "To debug, run fcitx5 in the foreground and look for"
    echo "'Loaded addon emojizasu-imd':"
    echo "  FCITX_ADDON_DIRS=$ADDON_DIRS fcitx5 -r"
    exit 1
fi

echo "Install complete — addon loaded and serving org.emojizasu.InputMethod."
echo "Run ./toggle.sh from the repo root to use the picker."
echo
echo "(Tests/CI export FCITX_ADDON_DIRS and launch their own fcitx5 directly.)"
