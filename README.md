# Emojizasu (絵文ジーザス)
An emoji picker with the goal of not being painful to use.
It roughly models Windows's emoji picker, which is one of the more impressive things to have come to Windows in a long time.
* Types emojis directly, versus clipboard
* Has kaomoji (`・ω・´)ゞ
* Localization

Still unfinished, so plenty of jank and churn.

## Prereqs
* Wayland (supporting `zwlr_layer_shell`, `zwp_text_input_manager`)
* fcitx5
* wl-clipboard

## Usage
First, review the code since nothing is in a stable state.

Install and run daemon via `imd/install.sh`.

Run `toggle.sh` and perhaps bind it to a key combination.

If the install reports the addon didn't come up, log out and back in once so the
session picks up `FCITX_ADDON_DIRS`. On KDE, `imd/reload.sh` reloads a rebuilt
addon via KWin's launcher (which `install.sh` uses automatically there).

## Why not...
* wtype: doesn't work on KDE Plasma
* kdotool/ydotool: no major reason
* IBus: because I don't use it, but would actually love to support it!

Once we got the fcitx5 solution working, things ended up going quite smoothly.
Also, if I'm not mistaken, ydotool require root, where this project doesn't.
Plus, this is certainly a valid use case for fcitx5 anyway.