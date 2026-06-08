import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Io
import "KeyNav.js" as KeyNav

Rectangle {
    id: root

    color: palette.window
    radius: 8

    signal emojiSelected(string emoji)
    signal closeRequested()

    property string language: "ja"
    property alias searchText: searchInput.text
    property string currentCategory: "recent"

    // Which UI zone keys/selection target. Values: "search", "categories", "grid".
    property string internalFocus: "grid"
    // True when the picker should hold real Wayland keyboard focus so the search
    // TextInput edits natively (Ctrl-A, selection, cursor).
    property bool wantsKeyboard: false
    property bool keyChannelDown: false
    property int gridSelectedIndex: 0

    property var emojiData: null
    property var categoryMeta: []
    property var recentList: []

    // Items fed into the three content views
    property var browseItems: []       // current category emoji
    property var kaomojiItems: []      // kaomoji category full list
    property var searchEmojiItems: []  // search: emoji matches
    property var searchKaomojiItems: [] // search: kaomoji matches

    readonly property bool dataReady: emojiData !== null
    readonly property bool isSearching: searchText.length > 0

    // Content index: 0=category browse, 1=kaomoji category, 2=search results
    readonly property int contentIndex: {
        if (isSearching) return 2
        if (currentCategory === "kaomoji") return 1
        return 0
    }

    readonly property int browseGridColumns: browseGrid.width > 0
        ? Math.max(1, Math.floor(browseGrid.width / browseGrid.cellWidth)) : 1
    readonly property int searchEmojiCols: searchFlickable.width > 0
        ? Math.max(1, Math.floor((searchFlickable.width + 2) / 44)) : 1
    readonly property int gridCount: contentIndex === 1 ? kaomojiItems.length
        : contentIndex === 2 ? (searchEmojiItems.length + searchKaomojiItems.length)
        : browseItems.length

    // True only in the test negative-control (EMOJIZASU_FORCE_FOCUSABLE): the
    // search field takes real keyboard focus and reproduces the focus-steal leak.
    // Disabled in normal operation.
    property bool forceFocusable: false

    function dlog(where, scope) {
        DebugLog.event(scope || "panel", where
            + "  internalFocus=" + internalFocus
            + " wantsKeyboard=" + wantsKeyboard
            + " searchFocus=" + searchInput.activeFocus
            + " gridSel=" + gridSelectedIndex
            + " searching=" + isSearching)
    }

    function focusSearch() { engageSearch() }

    function engageSearch() {
        internalFocus = "search"
        wantsKeyboard = true
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

    // From the search box, Tab/Down advance to the next zone: the results grid while
    // searching (categories are hidden), otherwise the category bar.
    function advanceFromSearch() {
        if (isSearching) focusGrid()
        else { internalFocus = "categories"; wantsKeyboard = false }
    }

    // Leave the grid backward (Shift-Tab, or Up from the top row): to the search box
    // while searching, otherwise to the category bar.
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
            searchInput.forceActiveFocus()
            dlog("forceActiveFocus(callLater)")
        })
        else searchInput.focus = false
    }

    // Click-out: if the search field loses real focus while we still think we're
    // searching, the user clicked away (e.g. back into the app) — give up keyboard
    // focus so keys reach the app again. (Depends on the compositor releasing the
    // layer surface's keyboard focus on outside-click.)
    Connections {
        target: searchInput
        function onActiveFocusChanged() {
            root.dlog("searchInput.activeFocusChanged=" + searchInput.activeFocus)
            if (!searchInput.activeFocus && root.internalFocus === "search" && !root.forceFocusable)
                root.releaseKeyboard()
        }
    }

    readonly property bool searchFocused: searchInput.activeFocus

    // Entry point for keystrokes forwarded by the addon (wire format
    // "<sym> <states> <text>"). The routing decision is pure (KeyNav.route parses
    // the line and picks an intent from the focused zone); this applies that
    // intent to the widgets.
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
        else wantsKeyboard = true
    }

    function insertInSearch(text) {
        ensureSearchEngaged()
        const p = searchInput.cursorPosition
        searchInput.text = searchInput.text.slice(0, p) + text + searchInput.text.slice(p)
        searchInput.cursorPosition = p + text.length
    }

    function clipboardInSearch(op) {
        ensureSearchEngaged()
        if (op === "selectAll") Qt.callLater(() => searchInput.selectAll())
        else if (op === "copy") Qt.callLater(() => searchInput.copy())
        else if (op === "cut") Qt.callLater(() => searchInput.cut())
        else if (op === "paste") Qt.callLater(() => searchInput.paste())
    }

    function deleteBackInSearch() {
        ensureSearchEngaged()
        const p = searchInput.cursorPosition
        if (p > 0) {
            searchInput.text = searchInput.text.slice(0, p - 1) + searchInput.text.slice(p)
            searchInput.cursorPosition = p - 1
        }
    }

    function moveSearchCursor(delta) {
        ensureSearchEngaged()
        const np = searchInput.cursorPosition + delta
        if (np >= 0 && np <= searchInput.text.length) searchInput.cursorPosition = np
    }

    function moveCategory(direction) {
        const ci = categoryMeta.findIndex(c => c.id === currentCategory)
        const target = direction === "left" ? ci - 1 : ci + 1
        if (target < 0 || target >= categoryMeta.length) return
        currentCategory = categoryMeta[target].id
        catBar.positionViewAtIndex(target, ListView.Contain)
    }

    // Whether the current grid selection sits in the first navigable row, so Up exits
    // the grid (like Shift-Tab) instead of moving within it.
    function gridAtTop() {
        if (contentIndex === 0)
            return gridSelectedIndex < browseGridColumns
        if (contentIndex === 2 && searchEmojiItems.length > 0)
            return gridSelectedIndex < Math.min(searchEmojiCols, searchEmojiItems.length)
        return gridSelectedIndex <= 0
    }

    function navigateGrid(direction) {
        if (direction === "up" && gridAtTop()) { leaveGridBackward(); return }
        if (gridSelectedIndex < 0) { gridSelectedIndex = 0; return }
        if (contentIndex === 0) {
            gridSelectedIndex = KeyNav.nextBrowseIndex(direction, gridSelectedIndex, browseGridColumns, browseItems.length)
            browseGrid.positionViewAtIndex(gridSelectedIndex, GridView.Contain)
        } else if (contentIndex === 1) {
            gridSelectedIndex = KeyNav.nextKaomojiIndex(direction, gridSelectedIndex, kaomojiItems.length)
            kaomojiList.positionViewAtIndex(gridSelectedIndex, ListView.Contain)
        } else if (contentIndex === 2) {
            gridSelectedIndex = KeyNav.nextSearchIndex(direction, gridSelectedIndex,
                searchEmojiItems.length, searchKaomojiItems.length, searchEmojiCols)
        }
    }

    function selectEmojiAt(idx) {
        if (contentIndex === 0) {
            if (idx >= 0 && idx < browseItems.length) emojiSelected(browseItems[idx].emoji)
        } else if (contentIndex === 1) {
            if (idx >= 0 && idx < kaomojiItems.length) emojiSelected(kaomojiItems[idx].text)
        } else if (contentIndex === 2) {
            const ei = searchEmojiItems.length
            if (idx < ei) {
                emojiSelected(searchEmojiItems[idx].emoji)
            } else {
                const ki = idx - ei
                if (ki < searchKaomojiItems.length) emojiSelected(searchKaomojiItems[ki].text)
            }
        }
    }

    // Commit the first item of whatever view is showing.
    function selectFirstEmoji() {
        if (isSearching) {
            if (searchEmojiItems.length > 0) { emojiSelected(searchEmojiItems[0].emoji); return }
            if (searchKaomojiItems.length > 0) { emojiSelected(searchKaomojiItems[0].text); return }
        } else if (currentCategory === "kaomoji") {
            if (kaomojiItems.length > 0) emojiSelected(kaomojiItems[0].text)
        } else if (browseItems.length > 0) {
            emojiSelected(browseItems[0].emoji)
        }
    }

    FileView {
        id: emojiDataFile
        // Resolve relative to this component's location (not shellDir) so the
        // picker loads its data when instantiated from any config dir, e.g. the
        // test harness's test/picker config.
        path: Qt.resolvedUrl("data/emoji.json")
        onLoaded: {
            root.emojiData = JSON.parse(emojiDataFile.text())
            root.buildCategoryMeta()
            root.refreshBrowse()
        }
    }

    FileView {
        id: recentFile
        path: StandardPaths.writableLocation(StandardPaths.StateLocation)
              + "/emojizasu/recent.json"
        printErrors: false
        onLoaded: {
            try { root.recentList = JSON.parse(recentFile.text()) }
            catch(e) { root.recentList = [] }
            if (root.currentCategory === "recent") root.refreshBrowse()
        }
        onFileChanged: recentFile.reload()
        onLoadFailed: root.recentList = []
    }

    Component.onCompleted: {
        if (forceFocusable)
            Qt.callLater(() => searchInput.forceActiveFocus())
    }

    function buildCategoryMeta() {
        if (!emojiData) return
        const cats = [{ id: "recent", icon: "🕐", name_en: "Recently Used", name_ja: "最近使った" }]
        for (let i = 0; i < emojiData.categories.length; i++) {
            const c = emojiData.categories[i]
            cats.push({ id: c.id, icon: c.icon, name_en: c.name_en, name_ja: c.name_ja })
        }
        cats.push({ id: "kaomoji", icon: "( ＾▽＾)", name_en: "Kaomoji", name_ja: "顔文字" })
        categoryMeta = cats
    }

    function refreshBrowse() {
        if (!emojiData) return
        if (currentCategory === "recent") {
            browseItems = recentList.map(e => ({ emoji: e, name_en: e, name_ja: e }))
            return
        }
        for (let i = 0; i < emojiData.categories.length; i++) {
            if (emojiData.categories[i].id === currentCategory) {
                browseItems = emojiData.categories[i].emoji
                return
            }
        }
        browseItems = []
    }

    function refreshKaomoji() {
        if (!emojiData) return
        kaomojiItems = emojiData.kaomoji
    }

    function refreshSearch() {
        if (!emojiData || searchText.length === 0) return
        const q = searchText
        const qlo = q.toLowerCase()
        const em = [], km = []

        for (let ci = 0; ci < emojiData.categories.length && em.length < 200; ci++) {
            const emojis = emojiData.categories[ci].emoji
            for (let ei = 0; ei < emojis.length && em.length < 200; ei++) {
                if (matchEmoji(emojis[ei], q, qlo)) em.push(emojis[ei])
            }
        }
        for (let ki = 0; ki < emojiData.kaomoji.length; ki++) {
            if (matchKaomoji(emojiData.kaomoji[ki], q, qlo)) km.push(emojiData.kaomoji[ki])
        }
        searchEmojiItems = em
        searchKaomojiItems = km
    }

    function matchEmoji(e, q, qlo) {
        if (e.emoji === q) return true
        if (e.name_en.toLowerCase().indexOf(qlo) >= 0) return true
        if (e.name_ja.indexOf(q) >= 0) return true
        const ke = e.keywords_en, kj = e.keywords_ja
        for (let i = 0; i < ke.length; i++) if (ke[i].toLowerCase().indexOf(qlo) >= 0) return true
        for (let j = 0; j < kj.length; j++) if (kj[j].indexOf(q) >= 0) return true
        return false
    }

    function matchKaomoji(km, q, qlo) {
        if (km.text.indexOf(q) >= 0) return true
        if (km.name_en.toLowerCase().indexOf(qlo) >= 0) return true
        if (km.name_ja.indexOf(q) >= 0) return true
        const t = km.tags
        for (let i = 0; i < t.length; i++) if (t[i].toLowerCase().indexOf(qlo) >= 0) return true
        return false
    }

    Timer {
        id: searchTimer; interval: 120; repeat: false
        onTriggered: root.refreshSearch()
    }

    onIsSearchingChanged: {
        gridSelectedIndex = isSearching ? 0 : (internalFocus === "grid" ? 0 : -1)
    }

    onCurrentCategoryChanged: {
        if (currentCategory === "kaomoji") refreshKaomoji()
        else refreshBrowse()
        if (internalFocus === "grid") gridSelectedIndex = 0
    }

    onSearchTextChanged: {
        if (searchText.length > 0) searchTimer.restart()
        if (internalFocus === "grid") gridSelectedIndex = 0
    }

    SystemPalette { id: palette; colorGroup: SystemPalette.Active }

    ColumnLayout {
        anchors { fill: parent; margins: 8 }
        spacing: 6

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                height: 34
                radius: 17
                color: palette.base
                border.color: (root.forceFocusable ? searchInput.activeFocus
                                                    : root.internalFocus === "search")
                              ? palette.highlight : Qt.darker(palette.base, 1.2)
                border.width: 1

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                    spacing: 6

                    Text {
                        text: "🔍"; font.pixelSize: 16; renderType: Text.NativeRendering
                    }

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            font.pixelSize: 14; color: palette.text
                            verticalAlignment: TextInput.AlignVCenter; clip: true
                            activeFocusOnPress: root.forceFocusable
                            cursorVisible: root.forceFocusable ? activeFocus
                                                               : root.internalFocus === "search"

                            Keys.onReturnPressed: { root.dlog("Qt Keys.Return"); root.selectFirstEmoji() }
                            Keys.onEnterPressed: { root.dlog("Qt Keys.Enter"); root.selectFirstEmoji() }
                            Keys.onEscapePressed: { root.dlog("Qt Keys.Escape"); root.closeRequested() }
                            Keys.onTabPressed: { root.dlog("Qt Keys.Tab"); root.advanceFromSearch() }
                            Keys.onBacktabPressed: { root.dlog("Qt Keys.Backtab"); root.internalFocus = "categories"; root.wantsKeyboard = false }
                            Keys.onDownPressed: { root.dlog("Qt Keys.Down"); root.advanceFromSearch() }
                        }

                        Text {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: root.language === "ja" ? "絵文字を検索..." : "Search emoji..."
                            color: Qt.alpha(palette.text, 0.38); font.pixelSize: 14
                            visible: searchInput.text.length === 0
                        }

                        // Click the search box to engage (take real keyboard focus);
                        // once engaged the MouseArea disables so clicks reach the
                        // TextInput for cursor positioning.
                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.wantsKeyboard && !root.forceFocusable
                            cursorShape: Qt.IBeamCursor
                            onClicked: root.engageSearch()
                        }
                    }

                    Text {
                        text: "✕"; font.pixelSize: 12
                        color: Qt.alpha(palette.text, 0.5)
                        visible: root.searchText.length > 0
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.searchText = ""
                                if (root.forceFocusable) searchInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            // Language toggle
            Rectangle {
                width: 46; height: 34; radius: 17
                color: langHover.containsMouse ? Qt.lighter(palette.button, 1.1) : palette.button
                border.color: Qt.darker(palette.button, 1.15); border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: root.language === "ja" ? "JA" : "EN"
                    font.pixelSize: 13; font.bold: true; color: palette.buttonText
                }
                MouseArea {
                    id: langHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.language = (root.language === "ja" ? "en" : "ja")
                }
            }

            // Close
            Rectangle {
                width: 34; height: 34; radius: 17
                color: xHover.containsMouse ? "#c0392b" : Qt.alpha(palette.button, 0.7)
                Text {
                    anchors.centerIn: parent; text: "✕"; font.pixelSize: 14
                    color: xHover.containsMouse ? "white" : palette.buttonText
                }
                MouseArea {
                    id: xHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested()
                }
            }
        }

        // Categories
        Rectangle {
            Layout.fillWidth: true
            height: 44
            color: "transparent"
            radius: 6
            border.color: root.internalFocus === "categories" ? Qt.alpha(palette.highlight, 0.6) : "transparent"
            border.width: 1
            visible: !root.isSearching

            ListView {
                id: catBar
                anchors.fill: parent; orientation: ListView.Horizontal; spacing: 1; clip: true
                model: root.categoryMeta
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }

                delegate: Item {
                    required property var modelData
                    width: 44; height: 44

                    Rectangle {
                        anchors { fill: parent; margins: 2 }
                        radius: 6
                        color: root.currentCategory === modelData.id
                               ? Qt.alpha(palette.highlight, 0.22)
                               : tabHover.containsMouse ? Qt.alpha(palette.highlight, 0.1) : "transparent"

                        Rectangle {
                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 1 }
                            width: 20; height: 2; radius: 1; color: palette.highlight
                            visible: root.currentCategory === modelData.id
                        }

                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            font.pixelSize: modelData.id === "kaomoji" ? 8 : 22
                            renderType: Text.NativeRendering
                        }

                        MouseArea {
                            id: tabHover; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentCategory = modelData.id
                                root.searchText = ""
                            }
                            ToolTip.visible: containsMouse; ToolTip.delay: 600
                            ToolTip.text: root.language === "ja" ? modelData.name_ja : modelData.name_en
                        }
                    }
                }
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true; height: 1; color: Qt.alpha(palette.windowText, 0.1)
            visible: !root.isSearching
        }

        // Status line
        Text {
            Layout.fillWidth: true
            font.pixelSize: 11; color: Qt.alpha(palette.windowText, 0.45)
            visible: root.dataReady
            text: {
                if (root.isSearching) {
                    const n = root.searchEmojiItems.length + root.searchKaomojiItems.length
                    return root.language === "ja" ? n + " 件の検索結果" : n + " results"
                }
                if (root.currentCategory === "recent")
                    return root.language === "ja" ? "最近使った絵文字" : "Recently used"
                if (root.currentCategory === "kaomoji")
                    return root.language === "ja" ? "顔文字  " + root.kaomojiItems.length + " 件" : root.kaomojiItems.length + " kaomoji"
                for (let i = 0; i < root.categoryMeta.length; i++) {
                    if (root.categoryMeta[i].id === root.currentCategory) {
                        const nm = root.language === "ja" ? root.categoryMeta[i].name_ja : root.categoryMeta[i].name_en
                        return nm + "  " + root.browseItems.length
                    }
                }
                return ""
            }
        }

        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: root.contentIndex

            // Category
            Item {
                GridView {
                    id: browseGrid
                    anchors.fill: parent; clip: true
                    cellWidth: 42; cellHeight: 42
                    model: root.browseItems
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: EmojiCell {
                        required property var modelData
                        required property int index
                        emojiChar: modelData.emoji
                        label: root.language === "ja" ? (modelData.name_ja || modelData.name_en) : modelData.name_en
                        selected: root.internalFocus === "grid" && index === root.gridSelectedIndex
                        onActivated: root.emojiSelected(emojiChar)
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: browseGrid.count === 0 && root.dataReady
                        text: root.currentCategory === "recent"
                              ? (root.language === "ja" ? "まだ使った絵文字がありません" : "No recently used emoji yet")
                              : (root.language === "ja" ? "絵文字がありません" : "No emoji here")
                        color: Qt.alpha(palette.windowText, 0.38); font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; width: 200
                    }
                }
            }

            // Kaomoji
            Item {
                ListView {
                    id: kaomojiList
                    anchors.fill: parent; clip: true; spacing: 1
                    model: root.kaomojiItems
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: KaomojiCell {
                        required property var modelData
                        required property int index
                        kaomojiText: modelData.text
                        label: root.language === "ja" ? modelData.name_ja : modelData.name_en
                        width: kaomojiList.width
                        highlight: index % 2 === 0
                        selected: root.internalFocus === "grid" && index === root.gridSelectedIndex
                        onActivated: root.emojiSelected(kaomojiText)
                    }
                }
            }

            // Search results
            Item {
                Flickable {
                    id: searchFlickable
                    anchors.fill: parent; clip: true
                    contentHeight: searchColumn.implicitHeight
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Column {
                        id: searchColumn
                        width: searchFlickable.width
                        spacing: 0

                        // Emoji results
                        Flow {
                            id: searchEmojiFlow
                            width: parent.width
                            spacing: 2
                            visible: root.searchEmojiItems.length > 0
                            Repeater {
                                model: root.searchEmojiItems
                                delegate: EmojiCell {
                                    required property var modelData
                                    required property int index
                                    emojiChar: modelData.emoji
                                    label: root.language === "ja" ? (modelData.name_ja || modelData.name_en) : modelData.name_en
                                    selected: root.internalFocus === "grid" && index === root.gridSelectedIndex
                                    onActivated: root.emojiSelected(emojiChar)
                                }
                            }
                        }

                        // Kaomoji results header
                        Item {
                            width: parent.width; height: 28
                            visible: root.searchKaomojiItems.length > 0 && root.searchEmojiItems.length > 0

                            Text {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 4 }
                                text: root.language === "ja" ? "顔文字" : "Kaomoji"
                                font.pixelSize: 11; font.bold: true
                                color: Qt.alpha(palette.windowText, 0.4)
                            }
                        }

                        // Kaomoji results list
                        Column {
                            width: parent.width
                            spacing: 1
                            visible: root.searchKaomojiItems.length > 0
                            Repeater {
                                model: root.searchKaomojiItems
                                delegate: KaomojiCell {
                                    required property var modelData
                                    required property int index
                                    kaomojiText: modelData.text
                                    label: root.language === "ja" ? modelData.name_ja : modelData.name_en
                                    width: searchColumn.width
                                    highlight: index % 2 === 0
                                    selected: root.internalFocus === "grid" && (root.searchEmojiItems.length + index) === root.gridSelectedIndex
                                    onActivated: root.emojiSelected(kaomojiText)
                                }
                            }
                        }

                        // Empty state
                        Item {
                            width: parent.width; height: 120
                            visible: root.searchEmojiItems.length === 0 && root.searchKaomojiItems.length === 0 && root.isSearching && root.dataReady
                            Text {
                                anchors.centerIn: parent
                                text: root.language === "ja" ? "「" + root.searchText + "」は見つかりませんでした" : "No results for \"" + root.searchText + "\""
                                color: Qt.alpha(palette.windowText, 0.38); font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; width: 260
                            }
                        }
                    }
                }
            }
        }
    }

    // Loading overlay
    Rectangle {
        anchors.fill: parent; radius: 8; color: palette.window
        visible: !root.dataReady

        Column {
            anchors.centerIn: parent; spacing: 12
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🌸"; font.pixelSize: 48; renderType: Text.NativeRendering
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.language === "ja" ? "読み込み中..." : "Loading..."
                color: Qt.alpha(palette.windowText, 0.5); font.pixelSize: 14
            }
        }
    }

    Rectangle {
        anchors.fill: parent; radius: 8; color: palette.window
        visible: root.keyChannelDown

        Column {
            anchors.centerIn: parent; spacing: 12; width: 300
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "⚠️"; font.pixelSize: 48; renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                text: root.language === "ja" ? "キー入力サービスに接続できません"
                                             : "Can't reach the key-input service"
                color: palette.windowText; font.pixelSize: 15; font.bold: true
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            }
            Text {
                width: parent.width
                text: root.language === "ja"
                      ? "fcitx5 と emojizasu アドオンが動作しているか確認してください"
                      : "Check that fcitx5 and the emojizasu addon are running, then reopen."
                color: Qt.alpha(palette.windowText, 0.55); font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            }
        }
    }
}
