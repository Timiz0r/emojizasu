#!/bin/bash
dir="$(dirname "$(readlink -f "$0")")"
qdbus6 org.kde.KWin /Scripting loadScript "$dir/kwin-refocus.js" emojizasu_refocus 2>/dev/null
qdbus6 org.kde.KWin /Scripting start 2>/dev/null
qdbus6 org.kde.KWin /Scripting unloadScript emojizasu_refocus 2>/dev/null
