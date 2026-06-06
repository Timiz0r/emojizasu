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

    property bool keyChannelDown: false

    onVisibleChanged: if (!visible) {
        keySocket.everConnected = false
        keyChannelDown = false
    }

    // D-Bus service to commit through. Defaults to production; the test harness
    // overrides it with EMOJIZASU_DBUS_NAME=org.emojizasu.InputMethodTest so the
    // real picker drives the isolated test addon.
    readonly property string dbusService: {
        const e = Quickshell.env("EMOJIZASU_DBUS_NAME")
        return (e && e.length > 0) ? e : "org.emojizasu.InputMethod"
    }
    readonly property string dbusInterface: "org.emojizasu.InputMethod"

    // Unix socket the addon forwards keystrokes over while the picker is up.
    // The addon never lets the picker take Wayland keyboard focus, so search /
    // navigation keys arrive through here instead. Mirrors dbusService: the test
    // harness points it at the test addon's socket via EMOJIZASU_KEY_SOCKET.
    readonly property string keySocketPath: {
        const e = Quickshell.env("EMOJIZASU_KEY_SOCKET")
        if (e && e.length > 0) return e
        const rt = Quickshell.env("XDG_RUNTIME_DIR")
        return (rt && rt.length > 0 ? rt : "/tmp") + "/emojizasu-imd.sock"
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
        // Simulate a key line the addon would forward over the socket
        // ("<sym> <states> <text>"), exercising the same path real keys take.
        function feedKey(line: string): void { panel.handleKeyLine(line) }
        function searchBoxText(): string { return panel.searchText }
        function searchBoxFocused(): bool { return panel.searchFocused }
        function isVisible(): bool { return window.visible }
        function focusSearch(): void { panel.focusSearch() }
    }

    // Keystrokes forwarded from the addon while the picker is visible. Connect
    // only while shown so the addon stops intercepting (passes keys to the app)
    // the moment the picker hides.
    Socket {
        id: keySocket
        path: window.keySocketPath
        connected: window.visible
        property bool everConnected: false
        parser: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { panel.handleKeyLine(line) }
        }
        onConnectionStateChanged: {
            if (connected) {
                everConnected = true
                window.keyChannelDown = false
            } else if (everConnected && window.visible) {
                console.warn("emojizasu: key socket dropped (search unusable)")
                window.keyChannelDown = true
            }
        }
        onError: function(err) {
            console.warn("emojizasu: cannot reach key socket (" + err + ")")
            if (window.visible) window.keyChannelDown = true
        }
    }

    EmojiPanel {
        id: panel
        anchors.fill: parent
        forceFocusable: window.forceFocusable
        keyChannelDown: window.keyChannelDown

        onEmojiSelected: function(emoji) {
            if (commitProcess.running) return
            commitProcess.command = [
                "qdbus6",
                window.dbusService,
                "/imd",
                window.dbusInterface + ".QueuedCommit",
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
