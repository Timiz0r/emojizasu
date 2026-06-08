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

    // KWin needs an explicit re-activation of the app window when the picker drops
    // keyboard focus; wlroots compositors return focus on their own, so the refocus
    // script is skipped there (it'd only fail anyway).
    readonly property bool isKwin: {
        const e = Quickshell.env("XDG_CURRENT_DESKTOP")
        return !!e && e.toLowerCase().indexOf("kde") !== -1
    }

    // The picker takes keyboard focus only while the search box is engaged
    // (panel.wantsKeyboard) so the TextInput edits natively; otherwise it stays
    // unfocused and search/nav keys are diverted through the addon's key socket.
    focusable: panel.wantsKeyboard || forceFocusable
    visible: false

    property bool keyChannelDown: false
    property string pendingEmoji: ""

    onVisibleChanged: if (!visible) {
        keySocket.everConnected = false
        keyChannelDown = false
        panel.resetFocusState()
    }

    // D-Bus service to commit through. Defaults to production; the test harness
    // overrides it with EMOJIZASU_DBUS_NAME=org.emojizasu.InputMethodTest so the
    // real picker drives the isolated test addon.
    readonly property string dbusService: {
        const e = Quickshell.env("EMOJIZASU_DBUS_NAME")
        return (e && e.length > 0) ? e : "org.emojizasu.InputMethod"
    }
    readonly property string dbusInterface: "org.emojizasu.InputMethod"

    // Unix socket the addon forwards keystrokes over while the picker is unfocused.
    // Overriden for tests via EMOJIZASU_KEY_SOCKET.
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

    // Keystrokes forwarded from the addon while the picker is unfocused (browsing /
    // type-to-search). When the search box engages, the picker takes real keyboard
    // focus and Qt delivers keys to the TextInput directly, so the socket
    // disconnects to avoid double-handling.
    Socket {
        id: keySocket
        path: window.keySocketPath
        connected: window.visible && !window.focusable
        property bool everConnected: false
        parser: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { panel.handleKeyLine(line) }
        }
        onConnectionStateChanged: {
            DebugLog.event("socket", "connected=" + connected
                + " visible=" + window.visible + " focusable=" + window.focusable)
            if (connected) {
                everConnected = true
                window.keyChannelDown = false
            } else if (everConnected && window.visible && !window.focusable) {
                console.warn("emojizasu: key socket dropped (search unusable)")
                window.keyChannelDown = true
            }
        }
        onError: function(err) {
            console.warn("emojizasu: cannot reach key socket (" + err + ")")
            if (window.visible && !window.focusable) window.keyChannelDown = true
        }
    }

    EmojiPanel {
        id: panel
        anchors.fill: parent
        forceFocusable: window.forceFocusable
        keyChannelDown: window.keyChannelDown

        onEmojiSelected: function(emoji) { window.commit(emoji) }
        onCloseRequested: window.visible = false
    }

    function dlog(where) { panel.dlog(where, "picker") }

    // Commit an emoji to the target app. If the picker holds keyboard focus (search
    // engaged), first release it and re-activate the target so the target is
    // fcitx5's current IC at commit time; otherwise commit directly.
    function commit(emoji) {
        dlog("commit('" + emoji + "') focusable=" + window.focusable
            + " yield=" + yieldTimer.running + " commit=" + commitProcess.running)
        if (yieldTimer.running || commitProcess.running) return
        if (!window.forceFocusable && window.focusable) {
            window.pendingEmoji = emoji
            panel.releaseKeyboard()
        } else {
            doCommit(emoji)
        }
    }

    function doCommit(emoji) {
        commitProcess.command = [
            "qdbus6", window.dbusService, "/imd",
            window.dbusInterface + ".QueuedCommit", emoji
        ]
        commitProcess.running = true
    }

    // Whenever the picker gives up keyboard focus while staying open, re-activate
    // the target app. During search the picker's TextInput becomes waylandim's
    // currentIC_ (mostRecentInputContext); KWin doesn't auto-return focus when the
    // layer surface drops it, so without this a later direct commit would target
    // the picker, not the app. A pending emoji means this release came from commit()
    // — the refocus then chains into the delayed commit; otherwise it's a plain
    // navigation/click-out release and just restores the app's IC.
    Connections {
        target: panel
        function onWantsKeyboardChanged() {
            if (!panel.wantsKeyboard && window.visible && !window.forceFocusable) {
                dlog("release refocus pendingEmoji='" + window.pendingEmoji + "'")
                if (window.isKwin) {
                    kwinRefocusProcess.running = true
                } else if (window.pendingEmoji.length > 0) {
                    yieldTimer.start()
                }
            }
        }
    }

    Process {
        id: kwinRefocusProcess
        command: [
            "bash", "-c",
            "printf '%s\\n'" +
            " 'var active = workspace.activeWindow;" +
            " var stack = workspace.stackingOrder;" +
            " for (var i = stack.length - 1; i >= 0; i--) {" +
            "   var w = stack[i];" +
            "   if (w && !w.deleted && w.normalWindow && w !== active) { workspace.activeWindow = w; break; }" +
            " }'" +
            " > /tmp/emojizasu-refocus.js &&" +
            " qdbus6 org.kde.KWin /Scripting loadScript /tmp/emojizasu-refocus.js emojizasu_refocus 2>/dev/null &&" +
            " qdbus6 org.kde.KWin /Scripting start 2>/dev/null &&" +
            " qdbus6 org.kde.KWin /Scripting unloadScript emojizasu_refocus 2>/dev/null; true"
        ]
        onExited: if (window.pendingEmoji.length > 0) yieldTimer.start()
    }

    Timer {
        id: yieldTimer
        interval: 1
        onTriggered: {
            window.doCommit(window.pendingEmoji)
            window.pendingEmoji = ""
        }
    }

    Process { id: commitProcess }

    Shortcut {
        sequence: "Escape"
        onActivated: window.visible = false
    }
}
