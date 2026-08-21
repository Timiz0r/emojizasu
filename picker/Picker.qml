import QtQuick
import Quickshell
import Quickshell.Io

PanelWindow {
    id: window
    color: "transparent"

    // The surface spans the whole output and stays put; the panel is positioned as a
    // child within it (panel.x/panel.y).
    // The input mask is pinned to the panel so clicks outside it pass through to the app behind.
    // A more normal attempt of positioning the window, or going with margins,
    // failed because the window would lag behind and "vibrate".
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    mask: Region { item: panel }

    property int panelWidth: 460
    property int panelHeight: 540
    onPanelWidthChanged: queueSaveGeometry()
    onPanelHeightChanged: queueSaveGeometry()

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

    // Keep the target application focused on every compositor. Search editing and
    // navigation are handled through the addon's key socket; making the layer
    // surface focusable here is unreliable on compositors such as niri.
    focusable: forceFocusable
    visible: false

    property bool positioned: false

    property bool keyChannelDown: false
    property string pendingEmoji: ""

    onVisibleChanged: {
        if (visible) {
            panel.refreshRecentSnapshot()
            if (!positioned) window.tryApplyInitialGeometry()
        } else {
            keySocket.everConnected = false
            keyChannelDown = false
            panel.resetFocusState()
        }
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

    // Persisted panel geometry, stored next to recent.json. Only seeds the first
    // show of a fresh process; within a process the live panel.x/y/size are kept.
    readonly property string statePath: {
        const base = Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
        return base + "/emojizasu/state.json"
    }

    property var savedGeometry: null

    // The layer surface isn't configured (window.width/height still 0) when the
    // picker first becomes visible, so defer positioning until it has a real size.
    // Clamping is done in window-space — the same frame drag/nudge/resize and the
    // saved values use — not screen-space, which on a multi-monitor setup is the
    // wrong output and would yank the panel onto the primary screen.
    function tryApplyInitialGeometry() {
        if (positioned || window.width <= 0 || window.height <= 0) return
        const g = window.savedGeometry || {}
        const w = (g.w > 0) ? g.w : panelWidth
        const h = (g.h > 0) ? g.h : panelHeight
        panelWidth  = Math.max(minPanelWidth,  Math.min(window.width,  w))
        panelHeight = Math.max(minPanelHeight, Math.min(window.height, h))
        let x = (typeof g.x === "number") ? g.x : -1
        let y = (typeof g.y === "number") ? g.y : -1
        if (x < 0 || y < 0) {
            x = Math.round((window.width  - panelWidth)  / 2)
            y = Math.round((window.height - panelHeight) / 2)
        }
        panel.x = Math.max(0, Math.min(window.width  - panelWidth,  x))
        panel.y = Math.max(0, Math.min(window.height - panelHeight, y))
        positioned = true
        DebugLog.event("geom", "saved=" + JSON.stringify(window.savedGeometry)
            + " window=" + window.width + "x" + window.height
            + " -> panel=" + panel.x + "," + panel.y + " size=" + panelWidth + "x" + panelHeight)
    }

    onWidthChanged: if (visible && !positioned) tryApplyInitialGeometry()
    onHeightChanged: if (visible && !positioned) tryApplyInitialGeometry()

    function queueSaveGeometry() {
        if (positioned) saveTimer.restart()
    }

    FileView {
        id: stateFile
        path: window.statePath
        blockLoading: true
        printErrors: false
        onLoaded: {
            let g = null
            try { g = JSON.parse(stateFile.text()) }
            catch (e) {}
            window.savedGeometry = g
            if (g && g.locale) Localization.localeCode = g.locale
        }
        onLoadFailed: window.savedGeometry = null
    }

    Connections {
        target: Localization
        function onLocaleCodeChanged() { if (window.positioned) saveTimer.restart() }
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: stateFile.setText(JSON.stringify({
            x: panel.x, y: panel.y, w: window.panelWidth, h: window.panelHeight,
            locale: Localization.localeCode
        }))
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
        function keyChannelConnected(): bool { return keySocket.connected }
        function isVisible(): bool { return window.visible }
        function focusSearch(): void { panel.focusSearch() }
    }

    // Keystrokes forwarded from the addon while browsing and searching. The target
    // application retains compositor keyboard focus, while fcitx consumes the keys
    // and sends them here for internal routing.
    Socket {
        id: keySocket
        path: window.keySocketPath
        connected: window.visible && !window.forceFocusable
        property bool everConnected: false
        parser: SplitParser {
            splitMarker: "\n"
            onRead: line => panel.handleKeyLine(line)
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
        onError: err => {
            console.warn("emojizasu: cannot reach key socket (" + err + ")")
            if (window.visible && !window.focusable) window.keyChannelDown = true
        }
    }

    EmojiPanel {
        id: panel
        width: window.panelWidth
        height: window.panelHeight
        dragMaxX: window.width - window.panelWidth
        dragMaxY: window.height - window.panelHeight
        forceFocusable: window.forceFocusable
        keyChannelDown: window.keyChannelDown

        onEmojiSelected: emoji => window.commit(emoji)
        onCloseRequested: window.visible = false
        onMoveWindowRequested: (dx, dy) => window.nudge(dx, dy)
        onResizeRequested: (w, h) => window.resize(w, h)
        onClipboardCopyRequested: text => window.copyToClipboard(text)
        onClipboardPasteRequested: window.pasteFromClipboard()
        onXChanged: window.queueSaveGeometry()
        onYChanged: window.queueSaveGeometry()
    }

    function dlog(where) { panel.dlog(where, "picker") }

    function nudge(dx, dy) {
        panel.x = Math.max(0, Math.min(window.width  - panelWidth,  panel.x + dx))
        panel.y = Math.max(0, Math.min(window.height - panelHeight, panel.y + dy))
    }

    readonly property int minPanelWidth: 320
    readonly property int minPanelHeight: 280

    function resize(w, h) {
        panelWidth  = Math.max(minPanelWidth,  Math.min(window.width  - panel.x, Math.round(w)))
        panelHeight = Math.max(minPanelHeight, Math.min(window.height - panel.y, Math.round(h)))
    }

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
            "busctl", "--user", "call", window.dbusService, "/imd",
            window.dbusInterface, "QueuedCommit", "s", emoji
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
        command: [Qt.resolvedUrl("kwin-refocus.sh").toString().slice(7)] // strip file://
        onExited: if (window.pendingEmoji.length > 0) yieldTimer.start()
    }

    Timer {
        id: yieldTimer
        interval: 0
        onTriggered: {
            window.doCommit(window.pendingEmoji)
            window.pendingEmoji = ""
        }
    }

    Process { id: commitProcess }

    property string pendingClipboardText: ""

    function copyToClipboard(text) {
        if (clipboardCopyProcess.running || text.length === 0) return
        pendingClipboardText = text
        clipboardCopyProcess.stdinEnabled = true
        clipboardCopyProcess.running = true
    }

    function pasteFromClipboard() {
        if (!clipboardPasteProcess.running)
            clipboardPasteProcess.running = true
    }

    Process {
        id: clipboardCopyProcess
        command: ["wl-copy", "--type", "text/plain;charset=utf-8"]
        onStarted: {
            write(window.pendingClipboardText)
            stdinEnabled = false
            window.pendingClipboardText = ""
        }
    }

    Process {
        id: clipboardPasteProcess
        command: ["wl-paste", "--no-newline", "--type", "text"]
        stdout: StdioCollector {
            onStreamFinished: panel.insertInSearch(text)
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: window.visible = false
    }

    Shortcut { sequence: "Ctrl+Shift+Left";  autoRepeat: true; onActivated: window.nudge(-10, 0) }
    Shortcut { sequence: "Ctrl+Shift+Right"; autoRepeat: true; onActivated: window.nudge( 10, 0) }
    Shortcut { sequence: "Ctrl+Shift+Up";    autoRepeat: true; onActivated: window.nudge(0, -10) }
    Shortcut { sequence: "Ctrl+Shift+Down";  autoRepeat: true; onActivated: window.nudge(0,  10) }
}
