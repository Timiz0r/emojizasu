import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "KeyNav.js" as KeyNav

Rectangle {
    id: root

    color: palette.window
    radius: 8

    signal emojiSelected(string emoji)
    signal closeRequested()
    signal moveWindowRequested(real dx, real dy)
    signal resizeRequested(real w, real h)
    signal clipboardCopyRequested(string text)
    signal clipboardPasteRequested()
    signal retryRequested()

    readonly property var t: Localization.t
    function _() { return Localization._.apply(null, arguments) }

    readonly property string language: Localization.localeCode
    property alias searchText: header.searchText
    property string currentCategory: "recent"

    property real dragMaxX: 0
    property real dragMaxY: 0

    property string internalFocus: "grid"
    property bool wantsKeyboard: false
    property bool keyChannelDown: false
    property int keyRetrySeconds: 0
    property int gridSelectedIndex: 0

    readonly property bool dataReady: EmojiData.dataReady

    readonly property var categoryMeta: {
        void EmojiData.changeTracking
        if (!EmojiData.dataReady) return []
        const cats = [], list = EmojiData.categories
        for (const id of list) {
            cats.push({ id: id, icon: EmojiData.catEmoji(id), name: EmojiData.catName(id) })
        }
        return cats
    }

    property var browseItems: currentCategory !== "recent"
        ? (EmojiData.categoryItems[currentCategory] || [])
        : []

    property var searchEmojiItems: []
    property var searchKaomojiItems: []

    property var recentEmojiItems: []
    property var recentKaomojiItems: []
    readonly property bool recentDataReady: EmojiData.recentDataReady

    function refreshRecentSnapshot() {
        recentEmojiItems = EmojiData.recentItems.filter(i => !EmojiData.kaomojis[i])
        recentKaomojiItems = EmojiData.recentItems.filter(i => EmojiData.kaomojis[i])
    }

    property bool forceFocusable: false

    readonly property bool isSearching: searchText.length > 0

    readonly property int browseGridColumns: browsePane.browseColumnCount
    readonly property int searchEmojiCols: searchPane.emojiColumnCount
    readonly property int recentEmojiCols: browsePane.recentColumnCount

    readonly property int gridCount: {
        if (isSearching) return searchEmojiItems.length + searchKaomojiItems.length
        if (currentCategory === "recent") return recentEmojiItems.length + recentKaomojiItems.length
        return browseItems.length
    }

    function dlog(where, scope) {
        DebugLog.event(scope || "panel", where
            + "  internalFocus=" + internalFocus
            + " wantsKeyboard=" + wantsKeyboard
            + " searchFocus=" + header.inputActiveFocus
            + " gridSel=" + gridSelectedIndex
            + " searching=" + isSearching)
    }

    function focusSearch() { engageSearch() }

    function engageSearch() {
        internalFocus = "search"
        dlog("engageSearch")
    }

    function releaseKeyboard() { wantsKeyboard = false; dlog("releaseKeyboard") }

    function focusGrid() {
        if (gridCount <= 0) return
        internalFocus = "grid"
        if (gridSelectedIndex < 0) gridSelectedIndex = 0
        wantsKeyboard = false
        dlog("focusGrid")
    }

    function advanceFromSearch() {
        if (isSearching) focusGrid()
        else { internalFocus = "categories"; wantsKeyboard = false }
    }

    function leaveGridBackward() {
        if (isSearching) engageSearch()
        else internalFocus = "categories"
        gridSelectedIndex = -1
    }

    function resetFocusState() {
        wantsKeyboard = false
        internalFocus = "grid"
        searchText = ""
        gridSelectedIndex = 0
        currentCategory = "recent"
    }

    onWantsKeyboardChanged: {
        if (wantsKeyboard) Qt.callLater(() => {
            header.focusInput()
            dlog("focusInput(callLater)")
        })
        else header.blurInput()
    }

    Connections {
        target: header
        function onInputFocusLost() {
            root.dlog("searchInput.activeFocusChanged=false")
            if (root.internalFocus === "search" && !root.forceFocusable)
                root.releaseKeyboard()
        }
        function onSearchAreaClicked() { root.engageSearch() }
        function onReturnKeyPressed() { root.dlog("Qt Keys.Return"); root.selectFirstEmoji() }
        function onEscapeKeyPressed() { root.dlog("Qt Keys.Escape"); root.closeRequested() }
        function onTabKeyPressed() { root.dlog("Qt Keys.Tab"); root.advanceFromSearch() }
        function onBacktabKeyPressed() { root.dlog("Qt Keys.Backtab"); root.internalFocus = "categories"; root.wantsKeyboard = false }
        function onDownKeyPressed() { root.dlog("Qt Keys.Down"); root.advanceFromSearch() }
    }

    readonly property bool searchFocused: header.inputActiveFocus

    function handleKeyLine(line) {
        const intent = KeyNav.route(line, internalFocus)
        dlog("handleKeyLine '" + line + "' -> " + intent.kind)
        switch (intent.kind) {
        case "close":
            closeRequested(); return
        case "activate":
            if (internalFocus === "grid" && gridSelectedIndex >= 0) selectEmojiAt(gridSelectedIndex)
            else selectFirstEmoji()
            return
        case "moveWindow":
            root.moveWindowRequested(intent.dx, intent.dy); return
        case "insert":
            insertInSearch(intent.text); return
        case "clipboard":
            clipboardInSearch(intent.op); return
        case "deleteBack":
            deleteBackInSearch(); return
        case "cursorLeft":
            moveSearchCursor(-1); return
        case "cursorRight":
            moveSearchCursor(1); return
        case "advanceFromSearch":
            advanceFromSearch(); return
        case "setCategory":
            moveCategory(intent.direction); return
        case "engageSearch":
            engageSearch(); return
        case "focusGrid":
            focusGrid(); return
        case "leaveGridBackward":
            leaveGridBackward(); return
        case "navGrid":
            navigateGrid(intent.direction); return
        default:
            return
        }
    }

    function ensureSearchEngaged() {
        if (internalFocus !== "search") engageSearch()
    }

    function insertInSearch(text) {
        ensureSearchEngaged()
        const start = header.searchSelectionStart
        const end = header.searchSelectionEnd
        header.searchText = header.searchText.slice(0, start) + text + header.searchText.slice(end)
        header.searchCursorPosition = start + text.length
    }

    function clipboardInSearch(op) {
        ensureSearchEngaged()
        if (op === "selectAll") header.selectAll()
        else if (op === "copy") {
            if (header.searchSelectedText.length > 0)
                clipboardCopyRequested(header.searchSelectedText)
        } else if (op === "cut") {
            if (header.searchSelectedText.length > 0) {
                clipboardCopyRequested(header.searchSelectedText)
                deleteSearchSelection()
            }
        } else if (op === "paste") {
            clipboardPasteRequested()
        }
    }

    function deleteSearchSelection() {
        const start = header.searchSelectionStart
        const end = header.searchSelectionEnd
        if (start === end) return false
        header.searchText = header.searchText.slice(0, start) + header.searchText.slice(end)
        header.searchCursorPosition = start
        return true
    }

    function deleteBackInSearch() {
        ensureSearchEngaged()
        if (deleteSearchSelection()) return
        const p = header.searchCursorPosition
        if (p > 0) {
            header.searchText = header.searchText.slice(0, p - 1) + header.searchText.slice(p)
            header.searchCursorPosition = p - 1
        }
    }

    function moveSearchCursor(delta) {
        ensureSearchEngaged()
        const start = header.searchSelectionStart
        const end = header.searchSelectionEnd
        if (start !== end) {
            header.searchCursorPosition = delta < 0 ? start : end
            header.deselect()
            return
        }
        const np = header.searchCursorPosition + delta
        if (np >= 0 && np <= header.searchText.length) header.searchCursorPosition = np
    }

    function moveCategory(direction) {
        catBar.moveTo(direction)
    }

    function gridAtTop() {
        if (!isSearching) {
            if (currentCategory === "recent") {
                if (recentEmojiItems.length > 0)
                    return gridSelectedIndex < Math.min(recentEmojiCols, recentEmojiItems.length)
                return gridSelectedIndex <= 0
            }
            if (currentCategory === "kaomoji") return gridSelectedIndex <= 0
            return gridSelectedIndex < browseGridColumns
        }
        if (searchEmojiItems.length > 0)
            return gridSelectedIndex < Math.min(searchEmojiCols, searchEmojiItems.length)
        return gridSelectedIndex <= 0
    }

    function navigateGrid(direction) {
        if (direction === "up" && gridAtTop()) { leaveGridBackward(); return }
        if (gridSelectedIndex < 0) { gridSelectedIndex = 0; return }
        if (!isSearching) {
            if (currentCategory === "recent") {
                gridSelectedIndex = KeyNav.nextSearchIndex(direction, gridSelectedIndex,
                    recentEmojiItems.length, recentKaomojiItems.length, recentEmojiCols)
                browsePane.ensureRecentVisible(gridSelectedIndex)
            } else if (currentCategory === "kaomoji") {
                gridSelectedIndex = KeyNav.nextKaomojiIndex(direction, gridSelectedIndex, browseItems.length)
                browsePane.positionKaomojiAt(gridSelectedIndex)
            } else {
                gridSelectedIndex = KeyNav.nextBrowseIndex(direction, gridSelectedIndex, browseGridColumns, browseItems.length)
                browsePane.positionBrowseAt(gridSelectedIndex)
            }
        } else {
            gridSelectedIndex = KeyNav.nextSearchIndex(direction, gridSelectedIndex,
                searchEmojiItems.length, searchKaomojiItems.length, searchEmojiCols)
        }
    }

    function selectEmojiAt(idx) {
        if (!isSearching) {
            if (currentCategory === "recent") {
                if (idx < recentEmojiItems.length) {
                    emojiSelected(recentEmojiItems[idx])
                } else {
                    const ki = idx - recentEmojiItems.length
                    if (ki < recentKaomojiItems.length) emojiSelected(recentKaomojiItems[ki])
                }
            } else if (idx >= 0 && idx < browseItems.length) {
                emojiSelected(browseItems[idx])
            }
        } else {
            const ei = searchEmojiItems.length
            if (idx < ei) {
                emojiSelected(searchEmojiItems[idx])
            } else {
                const ki = idx - ei
                if (ki < searchKaomojiItems.length) emojiSelected(searchKaomojiItems[ki])
            }
        }
    }

    function selectFirstEmoji() {
        if (isSearching) {
            if (searchEmojiItems.length > 0) { emojiSelected(searchEmojiItems[0]); return }
            if (searchKaomojiItems.length > 0) { emojiSelected(searchKaomojiItems[0]); return }
        } else if (browseItems.length > 0) {
            emojiSelected(browseItems[0])
        }
    }

    function refreshSearch() {
        if (!EmojiData.dataReady || searchText.length === 0) return
        const searchTerm = searchText.toLowerCase()
        const em = [], km = []
        const all = EmojiData.items
        for (const item of all) {
            if (em.length >= 200) break
            if (matchItem(item, searchTerm)) {
                if (EmojiData.kaomojis[item]) km.push(item)
                else em.push(item)
            }
        }
        searchEmojiItems = em
        searchKaomojiItems = km
    }

    function matchItem(item, searchTerm) {
        if (item === searchTerm) return true
        if (EmojiData.enNameFor(item).toLowerCase().indexOf(searchTerm) >= 0) return true
        const enKw = EmojiData.enKwFor(item)
        for (const kw of enKw) if (kw.toLowerCase().indexOf(searchTerm) >= 0) return true
        if (root.language !== "en") {
            if (EmojiData.nameFor(item).toLowerCase().indexOf(searchTerm) >= 0) return true
            const lKw = EmojiData.kwFor(item)
            for (const kw of lKw) if (kw.toLowerCase().indexOf(searchTerm) >= 0) return true
        }
        return false
    }

    Timer {
        id: searchTimer; interval: 120; repeat: false
        onTriggered: root.refreshSearch()
    }

    onDataReadyChanged: {
        if (dataReady) refreshRecentSnapshot()
    }

    onRecentDataReadyChanged: {
        if (recentDataReady) refreshRecentSnapshot()
    }

    onIsSearchingChanged: {
        gridSelectedIndex = isSearching ? 0 : (internalFocus === "grid" ? 0 : -1)
        if (!isSearching && currentCategory === "recent") refreshRecentSnapshot()
    }

    onCurrentCategoryChanged: {
        if (currentCategory === "recent") refreshRecentSnapshot()
        if (internalFocus === "grid") gridSelectedIndex = 0
    }

    onSearchTextChanged: {
        if (searchText.length > 0) searchTimer.restart()
    }

    Connections {
        target: EmojiData
        function onChangeTrackingChanged() { if (root.isSearching) root.refreshSearch() }
    }

    Component.onCompleted: {
        Localization.sources = [Qt.resolvedUrl("data/locale/ja.po")]
        if (forceFocusable)
            Qt.callLater(() => header.focusInput())
    }

    SystemPalette { id: palette; colorGroup: SystemPalette.Active }

    ColumnLayout {
        anchors { fill: parent; margins: 8 }
        spacing: 6

        PanelHeader {
            id: header
            Layout.fillWidth: true
            implicitHeight: 34
            dragTarget: root
            dragMaxX: root.dragMaxX
            dragMaxY: root.dragMaxY
            internalFocus: root.internalFocus
            wantsKeyboard: root.wantsKeyboard
            forceFocusable: root.forceFocusable
            language: root.language
            onCloseRequested: root.closeRequested()
        }

        // Only the body below the header swaps out for the loading and
        // disconnected states, so the drag handle, language toggle and close
        // button stay usable — otherwise the window could only be killed from
        // outside.
        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: !root.dataReady ? 1 : (root.keyChannelDown ? 2 : 0)

            ColumnLayout {
                spacing: 6

                CategoryBar {
                    id: catBar
                    Layout.fillWidth: true
                    height: 44
                    categoryMeta: root.categoryMeta
                    currentCategory: root.currentCategory
                    focused: root.internalFocus === "categories"
                    visible: !root.isSearching
                    onCategoryActivated: id => {
                        root.currentCategory = id
                        root.searchText = ""
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 1; color: Qt.alpha(palette.windowText, 0.1)
                    visible: !root.isSearching
                }

                Text {
                    Layout.fillWidth: true
                    font.pixelSize: 11; color: Qt.alpha(palette.windowText, 0.45)
                    text: {
                        if (root.isSearching) {
                            const n = root.searchEmojiItems.length + root.searchKaomojiItems.length
                            return _(t`${n} result`, n, { other: t`${n} results`, zero: t`No results` })
                        }
                        if (root.currentCategory === "recent")
                            return _`Recently used`
                        for (const meta of root.categoryMeta) {
                            if (meta.id === root.currentCategory) {
                                return meta.name + "  " + root.browseItems.length
                            }
                        }
                        return ""
                    }
                }

                StackLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    currentIndex: root.isSearching ? 1 : 0

                    BrowsePane {
                        id: browsePane
                        currentCategory: root.currentCategory
                        browseItems: root.browseItems
                        recentEmojiItems: root.recentEmojiItems
                        recentKaomojiItems: root.recentKaomojiItems
                        gridSelectedIndex: root.gridSelectedIndex
                        gridFocused: root.internalFocus === "grid"
                        dataReady: root.dataReady
                        onEmojiSelected: emoji => root.emojiSelected(emoji)
                    }

                    SearchPane {
                        id: searchPane
                        searchEmojiItems: root.searchEmojiItems
                        searchKaomojiItems: root.searchKaomojiItems
                        gridSelectedIndex: root.gridSelectedIndex
                        gridFocused: root.internalFocus === "grid"
                        isSearching: root.isSearching
                        dataReady: root.dataReady
                        searchText: root.searchText
                        onEmojiSelected: emoji => root.emojiSelected(emoji)
                    }
                }
            }

            Item {
                Column {
                    anchors.centerIn: parent; spacing: 12
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "🌸"; font.pixelSize: 48; renderType: Text.NativeRendering
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: _`Loading...`
                        color: Qt.alpha(palette.windowText, 0.5); font.pixelSize: 14
                    }
                }
            }

            Item {
                Column {
                    anchors.centerIn: parent; spacing: 12; width: 300
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "⚠️"; font.pixelSize: 40; renderType: Text.NativeRendering
                    }
                    Text {
                        width: parent.width
                        text: _`Can't reach the key-input service`
                        color: palette.windowText; font.pixelSize: 15; font.bold: true
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        text: _`Check that fcitx5 and the emojizasu addon are running.`
                        color: Qt.alpha(palette.windowText, 0.55); font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    }
                    Text {
                        width: parent.width
                        text: {
                            const n = root.keyRetrySeconds
                            if (n <= 0) return _`Reconnecting...`
                            return _(t`Retrying in ${n} second`, n, { other: t`Retrying in ${n} seconds` })
                        }
                        color: Qt.alpha(palette.windowText, 0.7); font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: retryLabel.implicitWidth + 24; height: 28; radius: 14
                        color: retryHover.containsMouse ? Qt.lighter(palette.button, 1.1) : palette.button
                        border.color: Qt.darker(palette.button, 1.15); border.width: 1
                        Text {
                            id: retryLabel
                            anchors.centerIn: parent
                            text: _`Retry now`
                            font.pixelSize: 12; color: palette.buttonText
                        }
                        MouseArea {
                            id: retryHover; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.retryRequested()
                        }
                    }
                }
            }
        }
    }

    Item {
        anchors { right: parent.right; bottom: parent.bottom }
        width: 16; height: 16

        Text {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 3; bottomMargin: 1 }
            text: "◢"
            font.pixelSize: 11
            renderType: Text.NativeRendering
            color: Qt.alpha(palette.windowText, resizeArea.containsMouse || resizeArea.pressed ? 0.7 : 0.3)
        }

        MouseArea {
            id: resizeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            property real pressSceneX
            property real pressSceneY
            property real pressW
            property real pressH
            onPressed: mouse => {
                const s = mapToItem(null, mouse.x, mouse.y)
                pressSceneX = s.x
                pressSceneY = s.y
                pressW = root.width
                pressH = root.height
            }
            onPositionChanged: mouse => {
                if (!pressed) return
                const s = mapToItem(null, mouse.x, mouse.y)
                root.resizeRequested(pressW + (s.x - pressSceneX), pressH + (s.y - pressSceneY))
            }
        }
    }
}
