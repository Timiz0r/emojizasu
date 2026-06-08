#!/usr/bin/env bash
# End-to-end emoji-commit tests.
#
# For each case the harness: focuses a target window, issues a QueuedCommit
# (exactly what the real picker does on an emoji click), then reads the target
# text back over IPC and asserts the emoji landed. This is the real pipeline:
# addon -> waylandim -> KWin -> target's text-input-v3.
#
# Drives the isolated test addon (org.emojizasu.InputMethodTest), which writes to
# its own recent.json (…/emojizasu-test/) — so runs never touch the production
# addon or your real recent list.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/target"
TARGET_TITLE="EmojizasuTestTarget"
SERVICE="org.emojizasu.InputMethodTest"
INTERFACE="org.emojizasu.InputMethod"
# Which compositor's IPC drives window focus. "kwin" = live KDE session;
# "sway" = headless sway (container/CI); "none" = rely on self-activation alone.
TEST_COMPOSITOR="${TEST_COMPOSITOR:?TEST_COMPOSITOR must be set}"
PICKER_SRC="$(cd "$SCRIPT_DIR/.." && pwd)/picker"   # the real picker UI folder
# A throwaway copy of the picker, run as its own qs config so it doesn't collide
# with the production instance (qs treats --path <root> and <root>/shell.qml as
# the same config). Copied (not symlinked) at startup, deleted on exit.
PICKER_DIR="$(mktemp -d /tmp/emojizasu-picker.XXXXXX)"
# A second throwaway copy, run with EMOJIZASU_FORCE_FOCUSABLE=1 for the negative
# control (the deliberately-broken, focus-stealing picker). Separate --path so it
# doesn't collide with the normal picker instance above.
PICKER_DIR_BROKEN="$(mktemp -d /tmp/emojizasu-picker-broken.XXXXXX)"

PASS=0 FAIL=0 SKIP=0

cleanup() {
    pkill -f -- "--path $TARGET_DIR" 2>/dev/null || true
    pkill -f -- "--path $PICKER_DIR" 2>/dev/null || true
    pkill -f -- "--path $PICKER_DIR_BROKEN" 2>/dev/null || true
    rm -f ${FOCUS_SCRIPT:+"$FOCUS_SCRIPT"}
    rm -rf "$PICKER_DIR" "$PICKER_DIR_BROKEN"
}
trap cleanup EXIT

log()  { echo "[test] $*"; }
ok()   { echo "  ✓ $*"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
skip() { echo "  ⊘ $*"; SKIP=$((SKIP+1)); }

imd()        { qdbus6 "$SERVICE" /imd "$INTERFACE.$1" "${@:2}"; }
tgt()        { qs ipc --path "$TARGET_DIR" call testtarget "$@" 2>/dev/null; }
pkr()        { qs ipc --path "$PICKER_DIR" call emojizasu "$@" 2>/dev/null; }
pkr_broken() { qs ipc --path "$PICKER_DIR_BROKEN" call emojizasu "$@" 2>/dev/null; }

# Compositor-specific window activation
case "$TEST_COMPOSITOR" in
  kwin)
    FOCUS_SCRIPT="$(mktemp /tmp/emojizasu_focus_XXXXXX.js)"
    cat > "$FOCUS_SCRIPT" <<EOF
var ws = workspace.windowList();
for (var i = 0; i < ws.length; i++) {
    if (ws[i].caption && ws[i].caption.indexOf("$TARGET_TITLE") >= 0) {
        workspace.activeWindow = ws[i];
        break;
    }
}
EOF
    focus_target() {
        qdbus6 org.kde.KWin /Scripting loadScript "$FOCUS_SCRIPT" emojizasu_focus &>/dev/null || true
        qdbus6 org.kde.KWin /Scripting start &>/dev/null || true
        qdbus6 org.kde.KWin /Scripting unloadScript emojizasu_focus &>/dev/null || true
    }
    ;;
  sway)
    focus_target() { swaymsg "[title=\"$TARGET_TITLE\"] focus" >/dev/null 2>&1 || true; }
    ;;
  *)
    echo "TEST_COMPOSITOR must be 'kwin' or 'sway', got '$TEST_COMPOSITOR'" >&2
    exit 1
    ;;
esac

ensure_focused() {
    for i in $(seq 1 20); do
        focus_target
        sleep 0.25
        [ "$(tgt isActive)" = "true" ] && return 0
    done
    return 1
}

expect_text() {
    local want="$1" got=""
    for i in $(seq 1 20); do
        got="$(tgt getText)"
        [ "$got" = "$want" ] && { echo "$got"; return 0; }
        sleep 0.1
    done
    echo "$got"; return 1
}

# Run one emoji-commit case end to end.
#   $1 name  $2 seed-text  $3..$N emojis to commit  (last arg implicitly = expected = seed+emojis)
commit_case() {
    local name="$1" seed="$2"; shift 2
    local emojis=("$@")
    local want="$seed"; for e in "${emojis[@]}"; do want+="$e"; done

    ensure_focused || { bad "$name (target never gained focus)"; return; }
    tgt clear >/dev/null
    [ -n "$seed" ] && tgt setText "$seed" >/dev/null
    for e in "${emojis[@]}"; do imd QueuedCommit "$e"; sleep 0.15; done

    local got="$(expect_text "$want")"
    if [ "$got" = "$want" ]; then ok "$name → '$got'"
    else bad "$name: expected '$want' got '$got'"; fi
}

# The test addon's key socket (test-variant uses emojizasu-imd-test.sock). Point
# the picker at it so it never connects to / triggers interception on the
# production addon's socket.
KEY_SOCKET="${XDG_RUNTIME_DIR:-/tmp}/emojizasu-imd-test.sock"

start_picker() {
    EMOJIZASU_DBUS_NAME="$SERVICE" EMOJIZASU_KEY_SOCKET="$KEY_SOCKET" \
        qs --path "$PICKER_DIR" &>/dev/null &
    for i in $(seq 1 40); do pkr hide &>/dev/null && return 0; sleep 0.1; done
    return 1
}

picker_ui_case() {
    local name="real picker: emoji lands in target, not search box" pick="🎯"
    start_picker   || { bad "$name (picker didn't start)"; return; }
    ensure_focused || { bad "$name (target never gained focus)"; return; }
    tgt clear >/dev/null
    pkr open >/dev/null
    sleep 0.3
    if [ "$(pkr isVisible)" != "true" ]; then bad "$name (picker not visible)"; return; fi
    pkr pick "$pick" >/dev/null

    local got search
    got="$(expect_text "$pick")"
    search="$(pkr searchBoxText)"
    if [ "$got" = "$pick" ] && [ -z "$search" ]; then
        ok "$name → target='$got', search box empty"
    else
        bad "$name: target='$got' (want '$pick'), searchBox='$search' (want empty)"
    fi
    pkr hide >/dev/null
    pkill -f -- "--path $PICKER_DIR" 2>/dev/null || true
}

# Forwarded keys (addon→socket→panel) drive the search box, with no Wayland
# keyboard focus on the picker. Uses the feedKey hook to inject wire-format key
# lines — the same path real keys take after the socket — so it runs without
# input synthesis. fcitx keysyms: c=99 a=97 t=116, BackSpace=0xff08=65288.
picker_search_input_case() {
    local name="real picker: forwarded keys type into search box"
    start_picker || { bad "$name (picker didn't start)"; return; }
    pkr open >/dev/null; sleep 0.2
    pkr feedKey "99 0 c" >/dev/null
    pkr feedKey "97 0 a"  >/dev/null
    pkr feedKey "116 0 t" >/dev/null
    sleep 0.1
    local s; s="$(pkr searchBoxText)"
    if [ "$s" = "cat" ]; then ok "$name → search='$s'"
    else bad "$name: search='$s' (want 'cat')"; fi

    pkr feedKey "65288 0 " >/dev/null; sleep 0.1
    s="$(pkr searchBoxText)"
    if [ "$s" = "ca" ]; then ok "$name: backspace → '$s'"
    else bad "$name: backspace got '$s' (want 'ca')"; fi
    pkr hide >/dev/null
    pkill -f -- "--path $PICKER_DIR" 2>/dev/null || true
}

start_picker_broken() {
    EMOJIZASU_DBUS_NAME="$SERVICE" EMOJIZASU_KEY_SOCKET="$KEY_SOCKET" EMOJIZASU_FORCE_FOCUSABLE=1 \
        qs --path "$PICKER_DIR_BROKEN" &>/dev/null &
    for i in $(seq 1 40); do pkr_broken hide &>/dev/null && return 0; sleep 0.1; done
    return 1
}

# Verifies that a certain bug on our end would exist,
# where the search box would be focused and cause emojis to show up there
#
# Compositor-specific: the focus-steal regression only reproduces on KWin.
picker_leak_control_case() {
    local name="negative control: broken picker leaks into search box" pick="🛑"
    if [ "$TEST_COMPOSITOR" != "kwin" ]; then
        skip "$name — KWin-specific (sway routes the commit to the target, no steal to catch)"
        return
    fi
    start_picker_broken || { bad "$name (broken picker didn't start)"; return; }
    ensure_focused      || { bad "$name (target never gained focus)"; return; }
    tgt clear >/dev/null
    pkr_broken open >/dev/null # focusable:true
    sleep 0.5
    if [ "$(pkr_broken isVisible)" != "true" ]; then bad "$name (picker not visible)"; return; fi
    pkr_broken focusSearch >/dev/null
    sleep 0.2
    pkr_broken pick "$pick" >/dev/null

    sleep 0.4
    local target_text search_text
    target_text="$(tgt getText)"
    search_text="$(pkr_broken searchBoxText)"
    if [ "$search_text" = "$pick" ] && [ "$target_text" != "$pick" ]; then
        ok "$name → leaked to search box (target='$target_text', search='$search_text')"
    else
        bad "$name: NO leak reproduced (target='$target_text', search='$search_text') — picker_ui_case can't catch the regression"
    fi
    pkr_broken hide >/dev/null
    pkill -f -- "--path $PICKER_DIR_BROKEN" 2>/dev/null || true
}

if ! imd GetRecent &>/dev/null; then
    echo "ERROR: $SERVICE not available — is the test addon loaded? (imd/install.sh + imd/reload.sh)" >&2
    exit 1
fi
log "test addon ($SERVICE) OK"

cleanup
mkdir -p "$PICKER_DIR" "$PICKER_DIR_BROKEN"
cp -r "$PICKER_SRC/." "$PICKER_DIR/"
cp -r "$PICKER_SRC/." "$PICKER_DIR_BROKEN/"

log "launching target window..."
qs --path "$TARGET_DIR" --no-duplicate &>/dev/null &
for i in $(seq 1 30); do tgt getText &>/dev/null && break; sleep 0.1; done

log "running cases..."
commit_case "commit into empty field"     ""      "🎉"
commit_case "append at cursor (seeded)"    "neko"  "🐱"
commit_case "multiple commits in a row"    ""      "🎉" "🔥" "💯"
picker_ui_case
picker_search_input_case
picker_leak_control_case

# Recent list reflects committed emoji.
ensure_focused && { tgt clear >/dev/null; imd QueuedCommit "🦄"; sleep 0.3; }
if imd GetRecent | grep -q "🦄"; then ok "recent list updated (contains 🦄)"
else bad "recent list missing 🦄: $(imd GetRecent)"; fi

echo
log "=== $PASS passed, $FAIL failed, $SKIP skipped (compositor: $TEST_COMPOSITOR) ==="
[ "$FAIL" -eq 0 ]
