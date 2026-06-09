#!/usr/bin/env bash
# Headless localization logic suite.
#
# Pure parse/plural/format logic — no compositor focus, no fcitx addon, no
# window. Runs the real picker/localization/*.js libs through qs (a QtObject
# shell, no PanelWindow) and asserts on the PASS/FAIL/SUMMARY lines it prints.
#
# qs sandboxes the config root and blackholes imports outside it, so the libs
# are copied next to the harness in a throwaway dir (the same copy-to-temp
# pattern tests.sh uses for the picker). Standalone-runnable; also invoked by
# test/tests.sh.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_SRC="$(cd "$SCRIPT_DIR/../.." && pwd)/picker/localization"
RUN_DIR="$(mktemp -d /tmp/emojizasu-loc.XXXXXX)"

cleanup() { rm -rf "$RUN_DIR"; }
trap cleanup EXIT

cp "$LIB_SRC"/Gettext.js "$LIB_SRC"/PoParser.js "$LIB_SRC"/PluralRules.js "$RUN_DIR/"
cp "$SCRIPT_DIR/shell.qml" "$RUN_DIR/"

OUT="$(timeout 60 qs --path "$RUN_DIR" 2>&1)"

echo "$OUT" | grep -oE '(PASS|FAIL) .*' | sed 's/^/  /'

SUMMARY="$(echo "$OUT" | grep -oE 'SUMMARY [0-9]+ [0-9]+' | tail -1)"
if [ -z "$SUMMARY" ]; then
    echo "[localization] ERROR: harness did not complete — raw output:" >&2
    echo "$OUT" >&2
    exit 1
fi

PASS="$(echo "$SUMMARY" | awk '{print $2}')"
FAIL="$(echo "$SUMMARY" | awk '{print $3}')"
echo "[localization] === $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
