import QtQuick
import Quickshell
import Quickshell.Io

PanelWindow {
    id: window
    implicitWidth: 460
    implicitHeight: 540

    // Test injection to verify failure can happen if true
    readonly property bool forceFocusable: {
        const e = Quickshell.env("EMOJIZASU_FORCE_FOCUSABLE")
        return e === "1" || e === "true"
    }
    focusable: forceFocusable
    visible: false

    // D-Bus service to commit through. Defaults to production; the test harness
    // overrides it with EMOJIZASU_DBUS_NAME=org.emojizasu.InputMethodTest so the
    // real picker drives the isolated test addon.
    readonly property string dbusService: {
        const e = Quickshell.env("EMOJIZASU_DBUS_NAME")
        return (e && e.length > 0) ? e : "org.emojizasu.InputMethod"
    }

    IpcHandler {
        target: "emojizasu"
        function toggle() {
            window.visible = !window.visible
        }
        // Named `open` (not `show`): `qs ipc call <t> show` collides with the
        // `qs ipc show` subcommand and silently no-ops.
        function open() {
            window.visible = true
        }
        function hide() {
            window.visible = false
        }
        // Test hooks
        function pick(emoji: string): void { panel.emojiSelected(emoji) }
        function searchBoxText(): string { return panel.searchText }
        function searchBoxFocused(): bool { return panel.searchFocused }
        function isVisible(): bool { return window.visible }
        function focusSearch(): void { panel.focusSearch() }
    }

    EmojiPanel {
        id: panel
        anchors.fill: parent

        onEmojiSelected: function(emoji) {
            if (commitProcess.running) return
            commitProcess.command = [
                "qdbus6",
                window.dbusService,
                "/imd",
                window.dbusService + ".QueuedCommit",
                emoji
            ]
            commitProcess.running = true
        }

        onCloseRequested: window.visible = false
    }

    Process {
        id: commitProcess
        onRunningChanged: {
            // Skip in forced-focusable mode: the negative control needs the
            // picker to keep keyboard focus through the commit so the leaked
            // emoji stays in the search box.
            if (!running && window.focusable && !window.forceFocusable) {
                // We had keyboard focus (search mode) — yield it so target IC activates
                window.focusable = false
                refocusTimer.start()
            }
        }
    }

    Timer {
        id: refocusTimer
        interval: 100
        onTriggered: window.focusable = true
    }

    Shortcut {
        sequence: "Escape"
        onActivated: window.visible = false
    }
}
